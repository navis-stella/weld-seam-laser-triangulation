function pointsCam = transformToCameraCoordinates(sensorPoints, ROI2fullImage, IntrinsicMatrix, planeCoeff)

    if isnan(sensorPoints)
        pointsCam = [NaN; NaN; NaN];

    else
        % Step 1: Express the points as homogeneous sensor coordinates
        numPoints = size(sensorPoints, 2);
        profileHomoPts = [sensorPoints;  ones(1,numPoints)];

        % Step 2: Convert point coordinates from the ROI to coordinates of the full image
%         ROI2fullImage = double([1 0 ROISample.OffsetX; 0 1 ROISample.OffsetY; 0 0 1]);
        fullImagePoints = ROI2fullImage * profileHomoPts;

        % Step 3: Transform points from the full image to camera coordinates
        scaleFactor = -planeCoeff(1) ./ ([planeCoeff(2) planeCoeff(3) -1] * (IntrinsicMatrix^-1 * fullImagePoints));
        pointsCam = (IntrinsicMatrix\fullImagePoints) .* scaleFactor;
    end

end
