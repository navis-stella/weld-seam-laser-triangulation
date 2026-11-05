function ptProfile = detectByIntensity(I)

I = imgaussfilt(I,0.6,'FilterSize',5);  % Filter the image with a Gaussian filter with standard deviation of 0.6
                                        % If you specify a scalar, then imgaussfilt uses a square filter. The default filter size is 2*ceil(2*sigma)+1.
ptProfile = nan(size(I,1),1);
for j = 1:size(I,1)

    imgTemp = double(I(j,:));
    imgTemp(:,1) = 0;
    imgTemp(:,end) = 0;

    [ptPeak,ptIndex] = max(imgTemp);
    if ptPeak > 5
        % Subpixel position: Gaussian fit through 3 points, delta = (ln a- - ln a+) / (2*(ln a+ - 2 ln a0 + ln a-))
        % (the parentheses around the denominator were missing before: it multiplied by 2*(...) instead of dividing)
        denom = 2*(log(imgTemp(ptIndex+1))-2*log(imgTemp(ptIndex))+ ...
            log(imgTemp(ptIndex-1)));
        if denom < 0
            delta = (log(imgTemp(ptIndex-1))-log(imgTemp(ptIndex+1)))/denom;
        else
            delta = 0;                  % flat maximum (e.g. saturation): whole pixel position
        end
        ptProfile(j)  = ptIndex + delta;
    end
end
ptProfile(isinf(ptProfile)) = NaN;
ptProfile = fillmissing(ptProfile,'nearest');
end

