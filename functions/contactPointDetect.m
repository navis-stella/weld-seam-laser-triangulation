function [ContactPoint, PointIndex] = contactPointDetect(baseLine3D, refDistance, direction)

ContactPoint = NaN; PointIndex = NaN;
% Find the contact point between the upper and lower sample piece along baseLine in 3D coordinates
switch direction
    case 'up'
        for ptNum = length(baseLine3D) : -1 : 1

            distance = norm(baseLine3D(:,ptNum) - baseLine3D(:,end));

            if distance >= refDistance
                ContactPoint = baseLine3D(:,ptNum);
                PointIndex = ptNum;
                break
            end

        end

    case 'down'
        for ptNum = 1 : 1 : length(baseLine3D)

            distance = norm(baseLine3D(:,ptNum) - baseLine3D(:,1));

            if distance >= refDistance
                ContactPoint = baseLine3D(:,ptNum);
                PointIndex = ptNum;
                break
            end

        end

end

end
