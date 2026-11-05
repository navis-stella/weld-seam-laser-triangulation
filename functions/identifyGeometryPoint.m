function [idTopPt, idBotPt, refTopPt, refBotPt] = identifyGeometryPoint(fitPrf, mSpt, mEpt, blUP, blLW, mCatpt)

    % No output values if no seam was identified
    if isnan(mSpt) || isnan(mEpt)
        idTopPt  = [NaN; NaN];        refTopPt = [NaN; NaN];
        idBotPt  = [NaN; NaN];        refBotPt = [NaN; NaN];

    else
    % Compute the middle segment
        midSegVal = fitPrf(mSpt:mEpt);
        if mSpt > mCatpt
            midBaseL = blLW(:,blLW(2,:)>=mSpt & blLW(2,:)<=mEpt);
        elseif mEpt > mCatpt
            midBLU = blUP(:,blUP(2,:)>=mSpt & blUP(2,:)<=mCatpt);
            midBLW = blLW(:,blLW(2,:)>=mCatpt & blLW(2,:)<=mEpt);
            midBaseL = [midBLU(:,1:end-1), (midBLU(:,end)+midBLW(:,1))/2,midBLW(:,2:end)];
        else
            midBaseL = blUP(:,blUP(2,:)>=mSpt & blUP(2,:)<=mEpt);
        end

            midSegoffset = midSegVal - midBaseL(1,:)';

        % Identify the highest point in the middle segment
        [~, idxMax] = max(midSegoffset);
        idTopPt = [fitPrf(midBaseL(2,idxMax)); midBaseL(2,idxMax)];

        % Identify the lowest point in the middle segment
        [~, idxMin] = min(midSegoffset);
        idBotPt = [fitPrf(midBaseL(2,idxMin)); midBaseL(2,idxMin)];

        %----------------------------------------------------------------------------
        % Determine the relevant baseline coordinates for the highest point
        if idTopPt(2,1) > mCatpt
            refTopPt = blLW(:, idTopPt(2,1) - blLW(2,1) + 1);
        else
            refTopPt = blUP(:, idTopPt(2,1));
        end

        % Determine the relevant baseline coordinates for the lowest point
        if idBotPt(2,1) > mCatpt
            refBotPt = blLW(:, idBotPt(2,1) - blLW(2,1) + 1);
        else
            refBotPt = blUP(:, idBotPt(2,1));
        end

        % If the detected point lies on the start or end point of the baseline, set it to NaN
        if idTopPt(2,1) == mSpt || idTopPt(2,1) == mEpt
            idTopPt  = [NaN; NaN];
            refTopPt = [NaN; NaN];
        end

        if idBotPt(2,1) == mSpt || idBotPt(2,1) == mEpt
            idBotPt  = [NaN; NaN];
            refBotPt = [NaN; NaN];
        end

    end
end
