function Recon = reconstructSeam3D(Result, triangulationParams, opt)
%% reconstructSeam3D - 3D surface of one sample from the laser line profiles of Step 2
%  Every image gives one profile in the laser plane and one known rotation angle.
%  Procedure:
%   1. Baselines of both pieces per image as in Step 2, repair of line errors outside the seam
%   2. All profiles from ROI coordinates to 3D camera coordinates
%   3. Rotation axis in the laser plane: direction from the line course averaged over
%      one revolution (the runout cancels out), position from the sample diameter
%   4. Polar coordinates around the rotation axis to a 3D surface
%   5. Alignment to the axis of the piece in the adapter (removes runout and tilt)
%   6. Height of every row relative to the baseline of its own piece
%
%  The offset of the two pieces stays in the coordinates X, Y and Recon.Deviation. Recon.Height
%  is free of it, because each piece is compared with its own baseline, so the surface next
%  to the seam does not appear sunken.
%
%  A line more than Result.Params.MinDip below the baseline outside the seam area counts as a
%  line error (reflection) and is interpolated along the profile. The surface of the pieces is
%  smooth, so a real scratch stays well below this limit.
%
%  The laser plane is assumed to contain the rotation axis. The images cannot show the
%  sense of rotation, so opt.RotationDirection decides it. Wrong value = mirrored sample,
%  all dimensions stay correct.
%
%  Inputs:
%    Result              - struct from evaluateSeamOfSample
%    triangulationParams - struct from Step 0 (cameraParams, laserPlaneNormal, laserPlaneCoeff)
%    opt                 - optional struct, fields see defaults below
%  Output:
%    Recon.X, Y, Z   - surface in mm (rows x images), Z from the adapter to the free end
%    Recon.Deviation - radial deviation from the nominal cylinder in mm, with the offset of the pieces
%    Recon.Height    - height relative to the baselines of Step 2 in mm, without the offset (dip negative)
%    Recon.Offset    - offset of the two pieces per image in mm (from Step 2)
%    Recon.LineError - rows x images, true where a line error was repaired
%    Recon.Arc       - unfolded position along the circumference in mm
%    Recon.SeamStart, Recon.SeamEnd - seam edges per image in mm along Z (NaN: no seam)
%    Recon.Runout, Recon.Tilt       - of the sample relative to the rotation axis (mm, °)

if nargin < 3, opt = struct(); end
defaults = struct('Diameter', 30, ...           % mm, nominal sample diameter
    'RotationDirection', 1, ...                 % 1: sample turns counterclockwise seen from the free end, -1: clockwise
    'SeamMargin', 15, ...                       % rows, distance of the reference rows from the seam area
    'EndMargin', 15, ...                        % rows, distance of the reference rows from the sample ends
    'MinRefRows', 30, ...                       % rows, minimum number of reference rows per piece
    'RepairPasses', 3);                         % repetitions of baseline and repair of line errors
fn = fieldnames(defaults);
for k = 1:numel(fn)
    if ~isfield(opt, fn{k}), opt.(fn{k}) = defaults.(fn{k}); end
end

R = opt.Diameter / 2;
xs = double(Result.Profile);
[nRows, n] = size(xs);

%% 1. Baselines of Step 2 and repair of line errors outside the seam
Z2 = Result.Rows;
nTop = Result.ROISeam.OffsetY - Result.ROISample.OffsetY + 1;
nBot = nTop + Result.ROISeam.Height - 1;
seamRows = max(1, nTop - Result.Params.WindowMargin) : min(nRows, nBot + Result.Params.WindowMargin);
smoothing = Result.Params.SgolayWindow;         % the smoothing of Step 2 spreads an error over this window

% A line error also tilts the baseline of its image, so baseline and repair are repeated
raw = xs;
for pass = 1:opt.RepairPasses
    base = baselinesOfStep2(xs, Z2);
    lineError = movmax(raw - base < -Result.Params.MinDip, smoothing, 1);
    lineError(seamRows,:) = false;
    xs = raw;
    xs(lineError) = NaN;
    xs = fillmissing(xs, 'linear', 1, 'EndValues', 'nearest');
end
base = baselinesOfStep2(xs, Z2);

%% 2. Profiles to 3D camera coordinates
cp = triangulationParams.cameraParams;
if isprop(cp, 'K'), K = cp.K; else, K = cp.IntrinsicMatrix'; end
E = triangulationParams.laserPlaneCoeff;
imgWidth = cp.ImageSize(2);
toCam = @(pts) roiToCamera(pts, Result.ROISample, imgWidth, Result.Params.MirrorX, K, E);

P = zeros(3, nRows, n);
for k = 1:n
    P(:,:,k) = toCam([xs(:,k)'; 1:nRows]);
end

% Reference rows on both sample pieces, outside the seam area
refAdapter = opt.EndMargin : nTop - opt.SeamMargin;
refFree    = nBot + opt.SeamMargin : nRows - opt.EndMargin;
if numel(refAdapter) < opt.MinRefRows || numel(refFree) < opt.MinRefRows
    error('%s: too few reference rows outside the seam area (%d and %d).', ...
        Result.Sample, numel(refAdapter), numel(refFree));
end
ref = [refAdapter refFree];

%% 3. Rotation axis in the laser plane
Pm = mean(P, 3, 'omitnan');                     % line course over one revolution
c  = mean(Pm(:,ref), 2);
[~, ~, V] = svd((Pm(:,ref) - c)', 'econ');
axisDir = V(:,1);
if dot(axisDir, Pm(:,end) - Pm(:,1)) < 0, axisDir = -axisDir; end
normal = triangulationParams.laserPlaneNormal(:) / norm(triangulationParams.laserPlaneNormal);
radial = cross(normal, axisDir);
if dot(radial, c) > 0, radial = -radial; end    % outwards, towards the camera

Pc = P - c;
t = squeeze(sum(Pc .* radial, 1));              % across the sample, in the laser plane
s = squeeze(sum(Pc .* axisDir, 1));             % along the sample
r = R + t - mean(t(refAdapter,:), 'all', 'omitnan');
z = s - mean(s(1,:), 'omitnan');

%% 4. Polar coordinates to the 3D surface
angle = -opt.RotationDirection * deg2rad(Result.Position(:)');   % position of the laser line on the sample
Xa = r .* cos(angle);
Ya = r .* sin(angle);

%% 5. Alignment to the axis of the piece in the adapter
% Centre of the circle per row (first harmonic of the radius), line through the centres
A = [ones(n,1) cos(angle') sin(angle')];
centre = A \ r(refAdapter,:)';
zRef = mean(z(refAdapter,:), 2);
pX = polyfit(zRef, centre(2,:)', 1);
pY = polyfit(zRef, centre(3,:)', 1);
ez = [pX(1); pY(1); 1] / norm([pX(1); pY(1); 1]);
ex = cross([0; 1; 0], ez);  ex = ex / norm(ex);
ey = cross(ez, ex);
dX = Xa - pX(2);  dY = Ya - pY(2);
X = ex(1)*dX + ex(2)*dY + ex(3)*z;
Y = ey(1)*dX + ey(2)*dY + ey(3)*z;
Z = ez(1)*dX + ez(2)*dY + ez(3)*z;

% Unfolded position, runs in the direction of Result.Position
Arc = -opt.RotationDirection * R * unwrap(atan2(Y, X), [], 2);

%% 6. Height relative to the baseline of the own piece
Height = nan(nRows, n);
for k = 1:n
    d = sqrt(sum((P(:,:,k) - toCam([base(:,k)'; 1:nRows])).^2, 1));
    Height(:,k) = sign(xs(:,k) - base(:,k))' .* d;
end

%% Result
Recon.Sample    = Result.Sample;
Recon.Diameter  = opt.Diameter;
Recon.Position  = Result.Position;
Recon.X         = single(X);
Recon.Y         = single(Y);
Recon.Z         = single(Z);
Recon.Deviation = single(hypot(X, Y) - R);
Recon.Height    = single(Height);
Recon.Arc       = single(Arc);
Recon.Offset    = Result.ContactOffset;
Recon.LineError = logical(lineError);
zRow = median(Z, 2);
Recon.SeamStart = rowToZ(Z2.SeamStart, zRow);
Recon.SeamEnd   = rowToZ(Z2.SeamEnd, zRow);
Recon.Runout    = hypot(pX(1)*zRef(1) + pX(2), pY(1)*zRef(1) + pY(2));
Recon.Tilt      = acosd(ez(3));
Recon.Params    = opt;
end

%% ------------------------------------------------------------------------
function base = baselinesOfStep2(xs, Z2)
% Baseline per row and image: top piece up to the contact point, bottom piece after it
    [nRows, n] = size(xs);
    base = zeros(nRows, n);
    for k = 1:n
        % Step 2 updates the window after the seam edges of image k, it is saved for image k+1
        next = min(k + 1, n);
        [blU, blL] = createBaseLines(xs(:,k), Z2.WindowStart(next), Z2.WindowEnd(next));
        cRow = Z2.Contact(k);
        if isnan(cRow), cRow = round((Z2.WindowStart(next) + Z2.WindowEnd(next)) / 2); end
        base(:,k) = [blU(1, 1:cRow), blL(1, cRow - blL(2,1) + 2 : end)];
    end
end

function z = rowToZ(rows, zRow)
% Row numbers (NaN allowed) to the position along Z
    z = nan(size(rows));
    valid = ~isnan(rows);
    z(valid) = zRow(rows(valid));
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
