function ptProfile = removeOutliers(ptProfile, windowSize, threshold)
    % Hampel filter for outlier removal
    k = (windowSize - 1) / 2;
    n = numel(ptProfile);
    for i = (k + 1):(n - k)
        window = ptProfile((i - k):(i + k));
        medianValue = median(window);
        mad = median(abs(window - medianValue));
        if abs(ptProfile(i) - medianValue) > threshold * mad
            ptProfile(i) = medianValue;
        end
    end
end
