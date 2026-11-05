function point = pointDetectionHessianMatrix(I, width, nPts)
%% pointDetectionHessianMatrix - Laser line detection via Steger's method
%  Inputs:
%    I     - Grayscale image (double, 0-1)
%    width - Expected laser line width in pixels (used to compute sigma);
%            start with about 1.5 x FWHM of the line profile
%    nPts  - Number of output points (evenly sampled along the fitted line)
%  Output:
%    point - [col, row] subpixel coordinates of laser line (nPts x 2)
%
%  CHANGES against the previous version (checked on synthetic lines with a Python port):
%   1. No zeroing of a 3 px image border. It created an artificial step where the
%      line reaches the image edge (errors up to 1.5 px within 4 px of the edge,
%      0.3-0.5 px within 8 px). hessian2D already uses 'replicate' padding.
%   2. Step 6 fits the line with an orientation-free total-least-squares fit (SVD)
%      instead of row = f(col). The old fit fails for near-vertical lines
%      (16 px offset and 25 deg angle error at 0 deg), and unique(round(col))
%      is not needed any more.
%   hessian2D now uses a kernel half size of ceil(3*sigma) (see hessian2D.m).

%% --- Parameters ---
COST_FUNCTION_WEIGHT      = 1.0;
ROUGHLY_PARALLEL_THRESHOLD = 360.0 / 32;

I0 = double(I);

%% --- Step 1: Hessian + Eigendecomposition ---
sigma = width / (2*sqrt(3));
[Dx, Dy, Dxx, Dxy, Dyy] = hessian2D(I0, sigma);
[Lambda1, ~, nx, ny, sx, sy] = eigImageHessian(Dxx, Dxy, Dyy);

% Subpixel displacement along normal direction (Steger 1998)
denom = Dxx.*nx.^2 + 2*Dxy.*nx.*ny + Dyy.*ny.^2;
denom(abs(denom) < eps) = eps;   % avoid division by zero
t  = -(Dx.*nx + Dy.*ny) ./ denom;
px = t .* nx;
py = t .* ny;

%% --- Step 2: Candidate Mask (vectorized) ---
Mask      = (abs(px) <= 0.5) & (abs(py) <= 0.5);
% Optional (not tested): only bright ridges, i.e. the dominant curvature is negative
% Mask    = Mask & (Lambda1 < 0);
Magnitude = Mask .* abs(Lambda1);

%% --- Step 3: Threshold candidates ---
nonzero_mag = Magnitude(Magnitude ~= 0);
if isempty(nonzero_mag)
    warning('pointDetectionHessianMatrix: No ridge candidates found!');
    point = [];
    return;
end
K0        = graythresh(nonzero_mag / max(nonzero_mag)) * max(nonzero_mag);
Threshold = [K0*0.3, K0*1.5];

% NOTE: Status is only set for pixels above Threshold(2), so the low threshold
% Threshold(1) has no effect in the tracing below (the test Magnitude >= Threshold(1)
% is always true). Setting Status for all pixels above Threshold(1) was tested and
% made the result worse (noise points joined the line), so it is left as it is.
check1       = Magnitude > Threshold(2);
[r1, c1]     = find(check1);
if isempty(r1)
    warning('pointDetectionHessianMatrix: No strong candidates above threshold!');
    point = [];
    return;
end

Pt1 = [r1, c1];
for k = 1:size(Pt1,1)
    Pt1(k,3) = Magnitude(Pt1(k,1), Pt1(k,2));
    Pt1(k,4) = atan2d(ny(Pt1(k,1), Pt1(k,2)), nx(Pt1(k,1), Pt1(k,2)));
    Pt1(k,5) = atan2d(sy(Pt1(k,1), Pt1(k,2)), sx(Pt1(k,1), Pt1(k,2)));
end
Pt1 = sortrows(Pt1, 3, 'descend');

Status = zeros(size(I0));
for k = 1:size(Pt1,1)
    Status(Pt1(k,1), Pt1(k,2)) = 1;
end

%% --- Step 4: Tracing (Steger line following) ---
lines_map = zeros(size(Pt1,1)*4, 4);  % pre-allocate
m1 = 1;

for i = 1:size(Pt1,1)
    if Status(Pt1(i,1), Pt1(i,2)) ~= 1
        continue;
    end

    % Store starting point
    lines_map(m1,:) = [Pt1(i,1), Pt1(i,2), px(Pt1(i,1),Pt1(i,2)), py(Pt1(i,1),Pt1(i,2))];
    m1 = m1 + 1;
    Status(Pt1(i,1), Pt1(i,2)) = 3;

    % Trace in both directions
    for direction = [1, -1]
        if direction == 1
            tp_sao = Pt1(i,5);
        else
            tp_sao = mod(Pt1(i,5) + 180.0, 360.0);
        end
        tp_px = Pt1(i,1);
        tp_py = Pt1(i,2);
        tracing = true;

        while tracing
            tp_sx  = sx(tp_px, tp_py);
            tp_sy  = sy(tp_px, tp_py);
            tp_sa  = atan2d(tp_sy, tp_sx);
            if abs(tp_sa - tp_sao) > 90.0
                tp_sx = -tp_sx;  tp_sy = -tp_sy;
                tp_sa = atan2d(tp_sy, tp_sx);
            end
            tp_si = getOrientationIndex(tp_sa);

            np_px = -1;  np_py = -1;
            last_cost = realmax('double');

            for j = -1:1
                tp_sic = mod(tp_si + j + 8, 8);  % cleaner wrap
                dp     = getNextPixel(tp_sic);
                dp_px  = tp_px + dp(1);
                dp_py  = tp_py + dp(2);
                if dp_px < 1 || dp_px > size(I0,1) || dp_py < 1 || dp_py > size(I0,2)
                    continue;
                end
                if Mask(dp_px, dp_py)
                    dp_sa = atan2d(sy(dp_px,dp_py), sx(dp_px,dp_py));
                    ddist_x = (dp_px + px(dp_px,dp_py)) - (tp_px + px(tp_px,tp_py));
                    ddist_y = (dp_py + py(dp_px,dp_py)) - (tp_py + py(tp_px,tp_py));
                    dtheta  = abs(dp_sa - tp_sa);
                    if dtheta > 90.0, dtheta = 180.0 - dtheta; end
                    cost = sqrt(ddist_x^2 + ddist_y^2) + COST_FUNCTION_WEIGHT * dtheta;
                    if cost < last_cost
                        last_cost = cost;
                        np_px = dp_px;  np_py = dp_py;
                    end
                end
            end

            if np_px == -1
                tracing = false;
                continue;
            end

            np_na = atan2d(ny(np_px,np_py), nx(np_px,np_py));
            np_ni = getOrientationIndex(np_na);
            np_sa = atan2d(sy(np_px,np_py), sx(np_px,np_py));
            if abs(np_sa - tp_sao) > 90.0
                np_sa = atan2d(-sy(np_px,np_py), -sx(np_px,np_py));
            end

            if Status(np_px, np_py) == 1
                if Magnitude(np_px, np_py) >= Threshold(1)
                    lines_map(m1,:) = [np_px, np_py, px(np_px,np_py), py(np_px,np_py)];
                    m1 = m1 + 1;
                    Status(np_px, np_py) = 3;
                    % Suppress parallel neighbors
                    for dd = [-1, 1]
                        pp2 = getNextPixel(np_ni);
                        nn_px = np_px + dd*pp2(1);
                        nn_py = np_py + dd*pp2(2);
                        if nn_px>=1 && nn_px<=size(I0,1) && nn_py>=1 && nn_py<=size(I0,2)
                            nn_na = atan2d(ny(nn_px,nn_py), nx(nn_px,nn_py));
                            if Status(nn_px,nn_py)==1 && ...
                               abs(mod(nn_na,180) - mod(np_na,180)) <= ROUGHLY_PARALLEL_THRESHOLD
                                Status(nn_px, nn_py) = 2;
                            end
                        end
                    end
                else
                    tracing = false;
                end
            else
                tracing = false;  % PROCESSED, LINEPOINT, or JUNCTION
            end
            tp_px = np_px;  tp_py = np_py;  tp_sao = np_sa;
        end
    end
end

%% --- Step 5: Extract subpixel points ---
lines_map = lines_map(1:m1-1, :);
lines_map = lines_map(any(lines_map ~= 0, 2), :);  % remove zero rows

if isempty(lines_map)
    warning('pointDetectionHessianMatrix: Tracing produced no points!');
    point = [];
    return;
end

% Subpixel positions: integer pixel + Hessian displacement
subpix_row = lines_map(:,1) + lines_map(:,3);  % row + dr
subpix_col = lines_map(:,2) + lines_map(:,4);  % col + dc

%% --- Step 6: Orientation-free line fit + deterministic resampling ---
% Total least squares (SVD) line through [col row], so near-vertical lines work.
% Outliers: absolute distance threshold to the line (no MAD, no rand()).
P = [subpix_col, subpix_row];                 % [u v]
if size(P,1) < 5
    warning('pointDetectionHessianMatrix: Too few points for fitting.');
    point = [];
    return;
end

OUTLIER_THRESHOLD_PX = 1.5;
c0 = mean(P, 1);
[~, ~, V] = svd(P - c0, 'econ');
for it = 1:2
    dist = abs((P - c0) * V(:,2));            % distance to the current line
    inl  = dist < OUTLIER_THRESHOLD_PX;
    % Fallback: if fewer than 50% are inliers the line is genuinely noisy -> use all
    if nnz(inl) < max(5, 0.5*numel(inl))
        inl = true(size(inl));
    end
    c0 = mean(P(inl,:), 1);
    [~, ~, V] = svd(P(inl,:) - c0, 'econ');
end
dirv = V(:,1)';                               % unit direction of the line [du dv]

% Evenly spaced deterministic resampling along the line (central 90 % of the inliers)
s     = sort((P(inl,:) - c0) * dirv');
s_lo  = s(max(1,   floor(0.05*numel(s))));
s_hi  = s(min(numel(s), floor(0.95*numel(s))));
ss    = linspace(s_lo, s_hi, nPts)';
point = c0 + ss * dirv;                       % [col, row]

end
