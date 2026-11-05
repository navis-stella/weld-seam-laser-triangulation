function [StartCoord,MiddCoord, EndCoord] = identifySeamSegment(ptProfile, estSeamStart, estSeamEnd, baseLineUpper, baseLineLower, deviationThreshold)

% Extract the horizontal coordinate
    baLiUpperU = baseLineUpper(1,:);
    baLiLowerU = baseLineLower(1,:);

% Compute the gradients
    gradientUpper = abs(diff(ptProfile(1:estSeamEnd+1)));
    gradientLower = abs(diff(ptProfile(estSeamStart-1:end)));

    % Determine the threshold for the gradient
    gradientThresholdStart = prctile(gradientUpper(estSeamStart-9:estSeamStart), 100);
    gradientThresholdEnd   = prctile(gradientLower((estSeamEnd-estSeamStart+1):estSeamEnd-estSeamStart+10), 100);

    % Initialize the start and end points
    seamStart = NaN;
    seamEnd   = NaN;

    % Identify the start point of the middle part
    for i = estSeamStart:estSeamEnd
        deviation = abs(ptProfile(i) - baLiUpperU(i));
        if any(deviation > deviationThreshold) && any(gradientUpper(i) > gradientThresholdStart)
            seamStart = i;
            break;
        end
    end

    % Identify the end point of the middle part
    for i = estSeamEnd:-1:estSeamStart
        % Baseline at row i (baseLineLower starts at row estSeamStart)
        deviation = abs(ptProfile(i) - baLiLowerU(i-estSeamStart+1));
        if any(deviation > deviationThreshold) && any(gradientLower(i-estSeamStart+1) > gradientThresholdEnd)
            seamEnd = i;
            break;
        end
    end

    % Check whether seamStart and seamEnd were found
    if ~isnan(seamStart) && ~isnan(seamEnd) && (seamEnd - seamStart >= 6)
        % Compute the midpoint of the middle segment
        seamMidd = floor((seamStart + seamEnd) / 2);
        % Compute the coordinates
        StartCoord = [ptProfile(seamStart); seamStart];
        MiddCoord  = [ptProfile(seamMidd);  seamMidd];
        EndCoord   = [ptProfile(seamEnd);   seamEnd];
    else
        StartCoord = [NaN; NaN];
        MiddCoord  = [NaN; NaN];
        EndCoord   = [NaN; NaN];
    end



end
