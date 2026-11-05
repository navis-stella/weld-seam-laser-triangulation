function Par = determineROIAndSeamArea(imgs, TopLength, BotLength, AdapterDepth, opt)
%% determineROIAndSeamArea - ROI of the laser line and seam area of one sample
%  The seam is found from the images of the sample itself: averaged over all
%  images of one revolution it appears as a bump in the laser line (to the right,
%  ReverseX = True). The nominal lengths only define the search range.
%
%  Inputs:
%    imgs         - images of one revolution (cell array, uint8)
%    TopLength    - length of the top sample piece in mm
%    BotLength    - length of the bottom sample piece in mm
%    AdapterDepth - insertion depth in the adapter in mm
%    opt          - optional struct, fields see defaults below
%  Output:
%    Par.ROISample, Par.ROISeam - OffsetX/OffsetY/Width/Height (pixels)
%    Par.SeamCenter             - row of the seam bump (pixels)
%    Par.SeamHeight             - height of the mean bump (pixels, line shift)
%    Par.SeamDetected           - false: bump too weak, nominal position ± opt.FallbackWidth
%    Par.Profile, Par.ProfileRows, Par.SearchRange - for display
%    Par.MeanLine               - mean line position per row of ProfileRows (column in the full image)

if nargin < 5, opt = struct(); end
defaults = struct('MarginLeft', 25, 'MarginRight', 45, ...   % px margin around the line (seam points to the right)
             'SearchRange', 60, ...                   % px, half width around the nominal seam position
             'SmoothWindow', 121, ...                 % rows, moving median for the surface trend
             'SeamMargin', 10, ...                    % px added above and below the bump
             'Threshold', 0.25, ...                   % fraction of the bump height for the area limit
             'ActivityThreshold', 0.5, ...            % px, deviation in 10 % of the images extends the area
             'MinHeight', 0.3, ...                    % px, a weaker bump counts as not detected
             'FallbackWidth', 20, ...                 % px, half window width without a detected bump
             'EndsStep', 4);                          % every n-th image for the sample ends
fn = fieldnames(defaults);
for k = 1:numel(fn)
    if ~isfield(opt, fn{k}), opt.(fn{k}) = defaults.(fn{k}); end
end

nImg = numel(imgs);
[~, nCols] = size(imgs{1});

%% 1. Sample ends (rows) per image, result = most frequent value
idxEnds = 1:opt.EndsStep:nImg;
Ends = nan(numel(idxEnds), 3);                         % [SmpTop SmpBot lineColumn]
for j = 1:numel(idxEnds)
    img = imgs{idxEnds(j)};
    lineCol = detectByIntensity(img);
    [~, SmpBot] = min(diff(lineCol));                   % free end face: largest jump to the left
    if SmpBot <= 6, continue, end
    lineLeft  = max(1,     round(lineCol(SmpBot-5) - 15));
    lineRight = min(nCols, round(lineCol(SmpBot-5) + 15));
    segment = filloutliers(detectByIntensity(img(1:SmpBot-5, lineLeft:lineRight)), 'linear', 'mean');
    [~, SmpTop] = min(diff(segment));                   % contact with the adapter
    SmpTop = SmpTop + 1;
    if SmpBot - SmpTop >= 120
        Ends(j,:) = [SmpTop, SmpBot, median(lineCol(SmpTop:SmpBot))];
    end
end
valid = ~isnan(Ends(:,1));
if nnz(valid) < 3
    error('Sample ends detected in only %d images.', nnz(valid));
end
SmpTop = mode(Ends(valid,1));
SmpBot = mode(Ends(valid,2));
colCenter = round(median(Ends(valid,3)));

%% 2. Laser line in all images (only columns around the line, without the background line)
col1 = max(1, colCenter - 80);  col2 = min(nCols, colCenter + 120);
rows = (SmpTop:SmpBot)';
X = zeros(numel(rows), nImg);
for k = 1:nImg
    X(:,k) = detectByIntensity(imgs{k}(rows, col1:col2)) + col1 - 1;
end
genuine = abs(X - median(X, 1)) < 15;                   % exclude false detections
SmpLft = max(1,     floor(min(X(genuine))) - opt.MarginLeft);
SmpRht = min(nCols, ceil(max(X(genuine)))  + opt.MarginRight);

%% 3. Seam bump in the mean line course of all images
%  The line position is subtracted per image (runout), then averaged over all images.
%  A moving median over opt.SmoothWindow rows gives the slow course of the sample
%  surface (curvature, tilt, offset of the two pieces). The difference from it
%  contains only narrow bumps such as the seam.
estSeamPos = SmpTop + round((SmpBot-SmpTop+1) * ...
    ((BotLength-AdapterDepth) / (BotLength - AdapterDepth + TopLength)));
r = rows - SmpTop + 1;                                  % local row number
inSearch = abs(rows - estSeamPos) <= opt.SearchRange;
Res = zeros(size(X));
for k = 1:nImg
    x = filloutliers(X(:,k), 'linear', 'movmedian', 31);
    Res(:,k) = x - polyval(polyfit(r, x, 1), r);
end
mRaw = movmean(mean(Res, 2), 5);
m = mRaw - movmedian(mRaw, opt.SmoothWindow, 'Endpoints', 'shrink');
baseVal = median(m(~inSearch));
mSearch = m;  mSearch(~inSearch) = -Inf;
[peak, iMax] = max(mSearch);
bumpHeight = peak - baseVal;

% Activity per row: 90th percentile of the deviation over all images. It also captures what the
% mean hides: dips and seam parts that occur only on part of the circumference.
H = Res - movmedian(Res, opt.SmoothWindow, 1, 'Endpoints', 'shrink');
A = movmean(prctile(abs(H), 90, 2), 5);
aBase = median(A(~inSearch));

if bumpHeight >= opt.MinHeight
    % Connected sections above the threshold; kept are the section with the maximum
    % and every further clear bump (> 50 %), e.g. for double peaks
    above = inSearch & (m > baseVal + opt.Threshold*bumpHeight);
    lab = cumsum([above(1); diff(above) == 1]) .* above;
    keep = false(size(m));
    for L = unique(lab(lab > 0))'
        section = lab == L;
        if section(iMax) || max(m(section)) > baseVal + 0.5*bumpHeight
            keep = keep | section;
        end
    end
    % Extend the area by connected rows with activity
    active = inSearch & (A > aBase + opt.ActivityThreshold);
    lab = cumsum([active(1); diff(active) == 1]) .* active;
    for L = unique(lab(lab > 0))'
        section = lab == L;
        if any(section & keep)
            keep = keep | section;
        end
    end
    SeamTop = rows(find(keep, 1, 'first')) - opt.SeamMargin;
    SeamBot = rows(find(keep, 1, 'last'))  + opt.SeamMargin;
    SeamCenter = rows(iMax);
    detected = true;
else
    SeamTop = estSeamPos - opt.FallbackWidth;
    SeamBot = estSeamPos + opt.FallbackWidth;
    SeamCenter = estSeamPos;
    detected = false;
end
SeamTop = max(SeamTop, SmpTop);  SeamBot = min(SeamBot, SmpBot);

%% Output
Par.ROISample = struct('OffsetX', SmpLft, 'OffsetY', SmpTop, ...
                       'Width', SmpRht - SmpLft + 1, 'Height', SmpBot - SmpTop + 1);
Par.ROISeam   = struct('OffsetX', SmpLft, 'OffsetY', SeamTop, ...
                       'Width', SmpRht - SmpLft + 1, 'Height', SeamBot - SeamTop + 1);
Par.SeamCenter   = SeamCenter;
Par.SeamHeight   = bumpHeight;
Par.SeamDetected = detected;
Par.NominalPos   = estSeamPos;
Par.Profile      = m - baseVal;
Par.ProfileRows  = rows;
Par.MeanLine     = median(X, 2);                        % line position per row (column in the full image), median over all images
Par.SearchRange  = estSeamPos + [-1 1]*opt.SearchRange;
Par.ValidImagesEnds = sprintf('%d/%d', nnz(valid), numel(idxEnds));
end
