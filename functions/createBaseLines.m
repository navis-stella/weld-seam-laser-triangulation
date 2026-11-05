function [baseLineUpper, baseLineLower] = createBaseLines(ptProfile, ptStart, ptEnd)

    % Baseline for the upper part
    pStart = polyfit(1:ptStart, ptProfile(1:ptStart), 1);
    baseLineUpper = [polyval(pStart, 1:ptEnd); 1:ptEnd];

    % Baseline for the lower part
    pEnd = polyfit(ptEnd:length(ptProfile), ptProfile(ptEnd:end), 1);
    baseLineLower = [polyval(pEnd, ptStart:length(ptProfile)); ptStart:length(ptProfile)];

end
