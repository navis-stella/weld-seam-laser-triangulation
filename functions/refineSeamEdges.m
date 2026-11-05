function [NS, NE] = refineSeamEdges(xs, NS, NE, blU, blL, eNS, eNE, nRef, factor, minThreshold, maxLead)
%% refineSeamEdges - correct seam edges triggered by noise
%  identifySeamSegment finds start and end via the gradient. In a wide window, noise
%  before the seam can trigger the start. Clear deviation from the respective
%  baseline: more than factor x noise (robust, from the nRef rows outside the window),
%  at least minThreshold px. If start or end lies more than maxLead rows before the
%  first or after the last clear deviation, the edge is set to that distance.
%  Otherwise it stays unchanged (seam transition from the gradient).
%  The edges are only moved inwards, never outwards.
%
%  Inputs:
%    xs         - smoothed line profile (column per row)
%    NS, NE     - start and end from identifySeamSegment (rows)
%    blU, blL   - baselines from createBaseLines(xs, eNS, eNE)
%    eNS, eNE   - current seam window
%  Outputs:
%    NS, NE     - corrected edges, NaN if no clear deviation remains

if isnan(NS) || isnan(NE), return, end
n = numel(xs);
refUp  = max(1, eNS - nRef) : eNS - 1;                  % rows above the window
refLow = eNE + 1 : min(n, eNE + nRef);                  % rows below the window
thrUp  = max(factor * robustNoise(xs(refUp) - blU(1, refUp)'), minThreshold);
thrLow = max(factor * robustNoise(xs(refLow) - blL(1, refLow - eNS + 1)'), minThreshold);

z = (NS:NE)';
devUp  = abs(xs(z) - blU(1, z)');                       % deviation from the upper baseline
devLow = abs(xs(z) - blL(1, z - eNS + 1)');             % deviation from the lower baseline
i1 = find(devUp > thrUp, 1, 'first');
i2 = find(devLow > thrLow, 1, 'last');
if isempty(i1) || isempty(i2) || i2 < i1
    NS = NaN;  NE = NaN;                                % no clear deviation: seam too small
    return
end
firstDev = NS + i1 - 1;
lastDev  = NS + i2 - 1;
NS = max(NS, firstDev - maxLead);
NE = min(NE, lastDev + maxLead);
if NE - NS < 6
    NS = NaN;  NE = NaN;
end
end

function s = robustNoise(res)
% Robust standard deviation: seam rows among the reference rows hardly increase it
    s = 1.4826 * median(abs(res - median(res)));
end
