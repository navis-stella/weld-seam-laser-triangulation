function [lambda1, lambda2, nx, ny, sx, sy] = eigImageHessian(Dxx, Dxy, Dyy)
% This function eig2image calculates the eigen values from the
% hessian matrix, sorted by abs value. And gives the direction
% of the normal (eigenvector largest eigenvalue).
% 
% [Lambda1,Lambda2,Ix,Iy]=eig2image(Dxx,Dxy,Dyy)
%
%
% | Dxx  Dxy |
% |          |
% | Dxy  Dyy |
%
% Adapted from eig2image.m by D.Kroon University of Twente
% Source: Hessian based Frangi Vesselness filter, MATLAB Central File Exchange no. 24409
% Copyright (c) 2009, Dirk-Jan Kroon. BSD licence, see LICENSE_Kroon.txt
% Modified for this project: both eigenvectors returned, sorting order changed

% Compute the eigenvalues
tmp = sqrt((Dxx - Dyy).^2 + 4*Dxy.^2);
mu1 = 0.5*(Dxx + Dyy + tmp);
mu2 = 0.5*(Dxx + Dyy - tmp);

% Compute the eigenvectors
v1x = 2*Dxy;
v1y = Dyy - Dxx + tmp;
v2x = 2*Dxy;
v2y = Dyy - Dxx - tmp;
% Normalization
mag_1 = sqrt(v1x.^2 + v1y.^2); 
i = (mag_1 ~= 0);
v1x(i) = v1x(i)./mag_1(i);
v1y(i) = v1y(i)./mag_1(i);
mag_2 = sqrt(v2x.^2 + v2y.^2); 
i = (mag_2 ~= 0);
v2x(i) = v2x(i)./mag_2(i);
v2y(i) = v2y(i)./mag_2(i);
% Sorting
check = abs(mu1) > abs(mu2); % lambda1 > lambda2
lambda1 = mu2; lambda1(check) = mu1(check);
lambda2 = mu1; lambda2(check) = mu2(check);
nx = v2x; nx(check) = v1x(check);
ny = v2y; ny(check) = v1y(check);
sx = v1x; sx(check) = v2x(check);
sy = v1y; sy(check) = v2y(check);

end