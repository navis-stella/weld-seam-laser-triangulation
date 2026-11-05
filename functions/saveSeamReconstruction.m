function saveSeamReconstruction(Recon, ResultsFolder, showFigs)
%% saveSeamReconstruction - save the 3D reconstruction of one sample and create the plots
%  Saved in the folder <ResultsFolder>\<Sample>:
%    Reconstruction3D.mat - struct Recon
%    Seam3D_Cylinder.jpg  - surface as the real sample, seen from two opposite sides
%    Seam3D_Unfolded.jpg  - cylinder unfolded into a plane, seen from the outside
%  The colour scales are the same for all samples, so the plots can be compared directly.

if nargin < 3, showFigs = false; end
target = fullfile(ResultsFolder, Recon.Sample);
if ~isfolder(target), mkdir(target); end

save(fullfile(target, 'Reconstruction3D.mat'), 'Recon');

vis = 'off';  if showFigs, vis = 'on'; end
heightLimit    = 2;     % mm, colour scale of the seam height
surfaceLimit   = 1;     % mm, colour scale of the whole sample
cmap = divergingMap();

%% Cylinder like the real sample
X = Recon.X(:, [1:end 1]);  Y = Recon.Y(:, [1:end 1]);  Z = Recon.Z(:, [1:end 1]);
C = Recon.Height(:, [1:end 1]);
sideViews = [-40 140];
f1 = figure('Name', 'Reconstruction as a cylinder', 'Visible', vis, 'Position', [200, 100, 1000, 700], 'Color', 'w');
tl = tiledlayout(f1, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for i = 1:2
    ax = nexttile(tl);
    surf(ax, X, Y, Z, C, 'EdgeColor', 'none', 'FaceColor', 'interp');
    axis(ax, 'equal');  clim(ax, heightLimit*[-1 1]);  colormap(ax, cmap);
    view(ax, sideViews(i), 18);
    % Soft light: strong shading would make the noise of the line detection look like a rough surface
    camlight(ax, 'headlight');  lighting(ax, 'gouraud');
    material(ax, [0.75 0.25 0]);
    xlabel(ax, 'X [mm]');  ylabel(ax, 'Y [mm]');  zlabel(ax, 'Height above the adapter [mm]');
    title(ax, sprintf('View from %d°', mod(sideViews(i), 360)));
end
cb = colorbar(ax);  cb.Layout.Tile = 'east';
cb.Label.String = 'Seam height relative to the baseline [mm]';
title(tl, Recon.Sample, 'Interpreter', 'none');
exportgraphics(f1, fullfile(target, 'Seam3D_Cylinder.jpg'), 'Resolution', 150);

%% Cylinder unfolded into a plane
circumference = pi * Recon.Diameter;
seam = [min(Recon.SeamStart) max(Recon.SeamEnd)] + [-3 3];
outward = Recon.Params.RotationDirection > 0;      % seen from the outside, Position runs from right to left
stretch = 3;                                       % seam area: stretched along the sample axis
zLimits = [min(Recon.Z(:)) max(Recon.Z(:))];
nWhole = round(diff(zLimits));
nSeam  = round(stretch * diff(seam));

% Figure height so that the whole sample has about equal scales in both directions
mapWidth = 950;
figHeight = 190 + mapWidth * (nWhole + nSeam) / circumference;
f2 = figure('Name', 'Reconstruction unfolded', 'Visible', vis, 'Position', [200, 50, 1150, figHeight], 'Color', 'w');
tl = tiledlayout(f2, nWhole + nSeam, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

ax = nexttile(tl, [nWhole 1]);
drawMap(ax, Recon.Arc, Recon.Z, Recon.Height, surfaceLimit, cmap, circumference, outward);
ylim(ax, zLimits);
ylabel(ax, 'Height above the adapter [mm]');
title(ax, sprintf('Whole sample: height relative to each piece, without the offset (offset median %.2f mm, max %.2f mm)', ...
    median(Recon.Offset, 'omitnan'), max(Recon.Offset)));
cb = colorbar(ax);  cb.Label.String = 'Height [mm]';

ax = nexttile(tl, [nSeam 1]);
drawMap(ax, Recon.Arc, Recon.Z, Recon.Height, heightLimit, cmap, circumference, outward);
hold(ax, 'on');
arcMid = median(Recon.Arc, 1);
top = max(Recon.Z(:));
plot3(ax, arcMid, Recon.SeamStart, top*ones(size(arcMid)), 'k.', 'MarkerSize', 2);
plot3(ax, arcMid, Recon.SeamEnd,   top*ones(size(arcMid)), 'k.', 'MarkerSize', 2);
hold(ax, 'off');
ylim(ax, seam);
xlabel(ax, 'Position along the circumference [mm]');  ylabel(ax, 'Height above the adapter [mm]');
title(ax, sprintf('Seam area, stretched %d times along the sample: height relative to the baseline, seam edges in black', stretch));
cb = colorbar(ax);  cb.Label.String = 'Seam height [mm]';

title(tl, Recon.Sample, 'Interpreter', 'none');
exportgraphics(f2, fullfile(target, 'Seam3D_Unfolded.jpg'), 'Resolution', 150);
if ~showFigs, close([f1 f2]); end
end

%% ------------------------------------------------------------------------
function drawMap(ax, arc, z, values, limit, cmap, circumference, reverseX)
% Map of the unfolded surface
    surf(ax, arc, z, zeros(size(z)), values, 'EdgeColor', 'none', 'FaceColor', 'interp');
    view(ax, 2);
    clim(ax, limit*[-1 1]);  colormap(ax, cmap);
    xlim(ax, [0 circumference]);
    if reverseX, ax.XDir = 'reverse'; end
    ax.Layer = 'top';
end

function cmap = divergingMap()
% Blue (dip), neutral grey (surface), red (bump)
    poles = [ 16  72 160;  84 138 214; 186 208 238; 226 225 222; 244 190 170; 216 104  70; 150  36  28] / 255;
    cmap = interp1(linspace(0, 1, size(poles,1)), poles, linspace(0, 1, 256));
end
