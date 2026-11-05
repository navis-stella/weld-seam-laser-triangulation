function orientation_index = getOrientationIndex(theta)
% if alpha < 0
%     alpha = alpha + 180.0;
% end
% Index = floor(alpha/(45));
if theta < 0
    theta = theta + 360.0;
end
theta_c = (theta + (180.0 / 8));
if theta_c >= 2 * 180.0
    theta_c = theta_c - 2 * 180.0;
end
orientation_index = floor(theta_c / (180.0 / 4));
end