function [Result, Strip] = evaluateSeamOfSample(file, triangulationParams, opt)
%% evaluateSeamOfSample - ROI, seam area and seam geometry of one sample
%  Procedure per sample:
%   1. Load the images and remove lens distortion
%   2. ROI of the laser line and seam area from the images of this sample (determineROIAndSeamArea)
%   3. Per image: detect the laser line in the ROI (only in a band around the mean line),
%      remove outliers, smooth, baselines of both sample pieces, seam segment,
%      contact point and offset of the sample pieces, highest/lowest point, conversion to mm
%
%  Inputs:
%    file       - full path of the image data (.mat with SampleImage, name with _T..B..)
%    triangulationParams - struct from Step 0 (cameraParams, laserPlaneCoeff)
%    opt        - optional struct, fields see defaults below
%  Outputs:
%    Result - results per image (height, width, depth, offset in mm, points, rows, profiles)
%    Strip  - ROI crops of all images (uint8), empty if opt.Strip = false

if nargin < 3, opt = struct(); end
defaults = struct('AdapterDepth', 2, ...        % mm, insertion depth in the adapter
    'MirrorX', false, ...                       % true: images are mirrored horizontally relative to the calibration
    'BandWidth', 12, ...                        % px, search band around the mean line position (outside the seam)
    'BandWidthSeam', 25, ...                    % px, search band in the seam area (deep dips, bumps)
    'HampelWindow', 11, 'HampelThreshold', 5, ...   % removeOutliers
    'SgolayOrder', 3, 'SgolayWindow', 11, ...       % smoothing
    'DeviationThreshold', 0.1, ...              % px, identifySeamSegment
    'MinDeviation', 0.3, ...                    % px, clear deviation from the baseline (seam, height, depth)
    'NoiseFactor', 3, 'NoiseRows', 30, ...      % refineSeamEdges: threshold = max(factor x noise, MinDeviation)
    'MaxLead', 5, ...                           % px, how far start/end may lie before the first clear deviation
    'MinDip', 1.0, ...                          % px (approx. 0.25 mm), minimum depth of a dip below the baseline
    'DipEdge', 3, ...                           % rows, a dip may not lie this close to the segment start/end
    'WindowMargin', 10, ...                     % px, how far the seam window may extend beyond the seam area of the sample
    'LengthTolerance', 0.03, ...                % deviation of the 3D length adapter to free end from the nominal length
    'Strip', true, ...                          % return ROI crops (e.g. for spatter)
    'ResultView', false, 'ViewStep', 1, ...     % show every n-th image
    'ViewPause', 0.2);                          % s, wait time after each displayed image
fn = fieldnames(defaults);
for k = 1:numel(fn)
    if ~isfield(opt, fn{k}), opt.(fn{k}) = defaults.(fn{k}); end
end

%% 1. Load the image data (old and new names) and remove lens distortion
[~, sample] = fileparts(file);
[TopLength, BotLength] = extractSampleLengths([sample '.mat']);
S = load(file);
if isfield(S, 'SampleImage'), P = S.SampleImage; else, P = S.ProbeImage; end   % ProbeImage: older recordings
clear S
imgField  = fieldName(P, {'imageData', 'vollImage'});
posField  = fieldName(P, {'imagePos',  'ImagePos'});
timeField = fieldName(P, {'timeStamp', 'Zeitstempel'});
present = ~cellfun(@isempty, {P.(imgField)});
if ~all(present)
    warning('%s: %d images are missing and will be skipped.', sample, nnz(~present));
end
imgs = {P(present).(imgField)};
pos  = [P(present).(posField)]';
timeSec = [P(present).(timeField)]';
clear P
if isdatetime(timeSec) || isduration(timeSec)
    timeSec = seconds(timeSec - timeSec(1));
else
    timeSec = double(timeSec - timeSec(1));
end

cp = triangulationParams.cameraParams;
for k = 1:numel(imgs)
    if opt.MirrorX
        % The calibration applies to unmirrored images: mirror back for undistortion
        imgs{k} = fliplr(undistortImage(fliplr(imgs{k}), cp));
    else
        imgs{k} = undistortImage(imgs{k}, cp);
    end
end

%% 2. ROI and seam area of this sample
Par = determineROIAndSeamArea(imgs, TopLength, BotLength, opt.AdapterDepth);
R = Par.ROISample;
rows = R.OffsetY : R.OffsetY + R.Height - 1;
cols = R.OffsetX : R.OffsetX + R.Width - 1;
nRows = numel(rows);
imgWidth = size(imgs{1}, 2);
if isprop(cp, 'K'), K = cp.K; else, K = cp.IntrinsicMatrix'; end   % K exists only from R2022b
E = triangulationParams.laserPlaneCoeff;
toCam = @(pts) roiToCamera(pts, R, imgWidth, opt.MirrorX, K, E);

lm = Par.MeanLine - R.OffsetX + 1;                    % mean line position (ROI columns)

% Calibration plausibility: 3D length from the adapter to the free end
pE = toCam([lm(1) lm(end); 1 nRows]);
sampleLen = norm(pE(:,2) - pE(:,1));
nominalLen = TopLength + BotLength - opt.AdapterDepth;
if abs(sampleLen/nominalLen - 1) > opt.LengthTolerance
    warning(['%s: 3D length adapter to free end %.1f mm instead of %.1f mm (%+.1f %%). ' ...
        'Check the calibration or MirrorX!'], sample, sampleLen, nominalLen, 100*(sampleLen/nominalLen - 1));
end

% Seam area of the sample in ROI rows; the adaptive window stays within these limits
nTop = Par.ROISeam.OffsetY - R.OffsetY + 1;
nBot = nTop + Par.ROISeam.Height - 1;
gMin = max(nTop - opt.WindowMargin, 12);
gMax = min(nBot + opt.WindowMargin, nRows - 11);
eNS = max(nTop, gMin);  eNE = min(nBot, gMax);

% Search band around the mean line position: wider in the seam area (spatter lies outside the seam)
band = opt.BandWidth * ones(nRows, 1);
band(max(1, nTop - opt.WindowMargin) : min(nRows, nBot + opt.WindowMargin)) = opt.BandWidthSeam;
mask = abs((1:numel(cols)) - lm) <= band;

%% 3. Evaluation per image
n = numel(imgs);
nanVec = nan(n, 1);  nanPts = nan(3, n);
Result.Height = nanVec;  Result.Width = nanVec;  Result.Depth = nanVec;  Result.ContactOffset = nanVec;
Z = struct('WindowStart', nanVec, 'WindowEnd', nanVec, 'SeamStart', nanVec, 'SeamEnd', nanVec, ...
           'Peak', nanVec, 'Valley', nanVec, 'Contact', nanVec);
Pts = struct('Start', nanPts, 'Middle', nanPts, 'End', nanPts, 'Peak', nanPts, 'Valley', nanPts, 'Contact', nanPts);
Profile = zeros(nRows, n, 'single');
if opt.Strip
    Strip = zeros(nRows, numel(cols), n, 'uint8');
else
    Strip = [];
end
if opt.ResultView
    % Separate window instead of output in the live script; the ROI is narrow and tall
    figure('Name', "Visual check " + sample, 'NumberTitle', 'off', 'Visible', 'on', ...
           'Units', 'normalized', 'OuterPosition', [0.05 0.05 0.25 0.9]);
end

for k = 1:n
    I = imgs{k}(rows, cols);
    if opt.Strip, Strip(:,:,k) = I; end
    Z.WindowStart(k) = eNS;  Z.WindowEnd(k) = eNE;

    %-- Detect the laser line in the search band, remove outliers, smooth
    Ib = I;  Ib(~mask) = 0;
    x  = hampelWithEdges(detectByIntensity(Ib), opt.HampelWindow, opt.HampelThreshold);
    xs = sgolayfilt(x, opt.SgolayOrder, opt.SgolayWindow);
    Profile(:,k) = xs;

    %-- Baselines and seam segment in the current window
    [blU, blL] = createBaseLines(xs, eNS, eNE);
    [pS, ~, pEn] = identifySeamSegment(xs, eNS, eNE, blU, blL, opt.DeviationThreshold);
    % Correct edges triggered by noise, discard seams that are too small
    [NS, NE] = refineSeamEdges(xs, pS(2), pEn(2), blU, blL, eNS, eNE, ...
                               opt.NoiseRows, opt.NoiseFactor, opt.MinDeviation, opt.MaxLead);
    if ~isnan(NS)
        NM  = floor((NS + NE) / 2);
        pS  = [xs(NS); NS];  pM = [xs(NM); NM];  pEn = [xs(NE); NE];
    end

    %-- Contact point of the sample pieces along the lower baseline, offset of the two baselines
    [cLow, cIdx] = contactPointDetect(toCam(blL), double(TopLength), 'up');
    if ~isnan(cIdx)
        cRow = blL(2, cIdx);
        pU = polyfit(blU(2,:), blU(1,:), 1);           % upper baseline, also beyond its end
        cUpp = toCam([polyval(pU, cRow); cRow]);
        Result.ContactOffset(k) = norm(cUpp - cLow);
        Pts.Contact(:,k) = (cUpp + cLow) / 2;
        Z.Contact(k) = cRow;
    else
        cRow = NaN;
    end

    if ~isnan(NS) && ~isnan(NE)
        %-- Window for the next image: detected seam edges ± 5 px, but never narrower than the seam area
        %   of the sample (otherwise e.g. the dip of an S-shaped seam is missed) and not beyond its limit
        eNS = min(max(min(nTop, NS - 5), gMin), gMax);  eNE = max(min(max(nBot, NE + 5), gMax), gMin);

        [blU, blL] = createBaseLines(xs, eNS, eNE);
        [peak, valley, refP, refV] = identifyGeometryPoint(xs, NS, NE, blU, blL, cRow);

        Pts.Start(:,k) = toCam(pS);  Pts.Middle(:,k) = toCam(pM);  Pts.End(:,k) = toCam(pEn);
        Pts.Peak(:,k) = toCam(peak);  Pts.Valley(:,k) = toCam(valley);
        rP = toCam(refP);  rV = toCam(refV);

        Result.Width(k) = norm(Pts.End(:,k) - Pts.Start(:,k));
        % Height only if the peak lies clearly outside the baseline (to the right in the image).
        % Depth (negative) only for a real dip: line more than MinDip below the baseline
        % and not at the edge of the segment (there the deviation comes from the baseline offset)
        if peak(1) - refP(1) > opt.MinDeviation
            Result.Height(k) = norm(Pts.Peak(:,k) - rP);
        end
        if valley(1) - refV(1) < -opt.MinDip && valley(2) - NS >= opt.DipEdge && NE - valley(2) >= opt.DipEdge
            Result.Depth(k) = -norm(Pts.Valley(:,k) - rV);
        end
        Z.SeamStart(k) = NS;  Z.SeamEnd(k) = NE;  Z.Peak(k) = peak(2);  Z.Valley(k) = valley(2);
    else
        % Seam not detected: reset the window to the seam area of the sample
        % (the last valid window can be too narrow and would otherwise stay stuck)
        eNS = max(nTop, gMin);  eNE = min(nBot, gMax);
    end

    %-- Visual check in the ROI (every n-th image)
    if opt.ResultView && mod(k-1, opt.ViewStep) == 0
        showROI(I, xs, blU, blL, Z, k, peakOrNaN(Z, k, xs), ~isnan(Result.Depth(k)), sample, n);
        pause(opt.ViewPause);
    end
end

%% Result
Result.Sample        = sample;
Result.File          = file;
Result.TopLength     = TopLength;
Result.BotLength     = BotLength;
Result.Position      = pos;
Result.Time          = timeSec;
Result.Rows          = Z;
Result.Points        = Pts;
Result.Profile       = Profile;
Result.ROISample     = R;
Result.ROISeam       = Par.ROISeam;
Result.SeamCenterROI = Par.SeamCenter - R.OffsetY + 1;
Result.Length        = sampleLen;
Result.NominalLength = nominalLen;
Result.ROIDetails    = rmfield(Par, {'ROISample', 'ROISeam'});
Result.Params        = opt;
end

%% ------------------------------------------------------------------------
function name = fieldName(P, candidates)
% First existing field name (new and old names of the image acquisition)
    for i = 1:numel(candidates)
        if isfield(P, candidates{i}), name = candidates{i}; return, end
    end
    error('None of the fields %s found in the image data.', strjoin(candidates, ', '));
end

function X = roiToCamera(pts, R, imgWidth, mirror, K, E)
% ROI coordinates [u; v] (1-based) to 3D camera coordinates (mm)
    u = pts(1,:) + R.OffsetX - 1;
    v = pts(2,:) + R.OffsetY - 1;
    if mirror
        u = imgWidth + 1 - u;            % column in the unmirrored calibration image
    end
    X = transformToCameraCoordinates([u; v], eye(3), K, E);
end

function x = hampelWithEdges(x, window, threshold)
% removeOutliers also for the first and last rows (continued by mirroring)
    k = (window - 1) / 2;
    xp = [flipud(x(2:k+1)); x; flipud(x(end-k:end-1))];
    xp = removeOutliers(xp, window, threshold);
    x = xp(k+1 : end-k);
end

function g = peakOrNaN(Z, k, xs)
% Peak [u; v] of image k for the display
    if isnan(Z.Peak(k)), g = [NaN; NaN]; else, g = [xs(Z.Peak(k)); Z.Peak(k)]; end
end

function showROI(I, xs, blU, blL, Z, k, peak, hasDip, sample, n)
% Display: profile, baselines, seam segment, peak, dip, window
    v = (1:numel(xs))';
    imshow(I, 'InitialMagnification', 'fit'); hold on
    plot(xs, v, 'b-', 'LineWidth', 1.5);
    plot(blU(1,:), blU(2,:), 'g--', blL(1,:), blL(2,:), 'y--');
    NS = Z.SeamStart(k);  NE = Z.SeamEnd(k);
    if ~isnan(NS)
        plot(xs(NS:NE), v(NS:NE), 'r-', 'LineWidth', 2);
        % plot(xs(NS), NS, 'rx', xs(NE), NE, 'gx', 'MarkerSize', 6);
    end
    if ~isnan(peak(1)), plot(peak(1), peak(2), 'yo', 'MarkerFaceColor', 'y','MarkerSize', 3); end
    if hasDip, plot(xs(Z.Valley(k)), Z.Valley(k), 'co', 'MarkerFaceColor', 'c', 'MarkerSize', 3); end
    if ~isnan(Z.Contact(k)), yline(Z.Contact(k), ':', 'Color', '#4DBEEE', 'LineWidth', 1); end
    yline([Z.WindowStart(k) Z.WindowEnd(k)], 'w-.');
    hold off
    title(sprintf('%s: image %d/%d', sample, k, n), 'Interpreter', 'none');
    drawnow
end
