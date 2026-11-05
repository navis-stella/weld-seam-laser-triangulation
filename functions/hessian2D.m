function [Dx,Dy,Dxx,Dxy,Dyy] = hessian2D(I, sigma)
%  This function Hessian2 Filters the image with 2nd derivatives of a
%  Gaussian with parameter Sigma.
%
% [Dx,Dy,Dxx,Dxy,Dyy] = hessian2D(I,Sigma);
%
% inputs,
%   I : The image, class preferable double or single
%   Sigma : The sigma of the gaussian kernel used
%
% outputs,
%   Dx, Dy, Dxx, Dxy, Dyy: 1st and 2nd derivatives
%   (x = 1st array dimension = rows, y = 2nd dimension = columns)
%
% Function is written by D.Kroon University of Twente (June 2009)
% Source: Hessian based Frangi Vesselness filter, MATLAB Central File Exchange no. 24409
% Copyright (c) 2009, Dirk-Jan Kroon. BSD licence, see LICENSE_Kroon.txt
% Modified for this project: first derivatives added, replicate border handling, kernel size
%
% CHANGE: kernel half size was 2*round(sigma) (only 1.7 sigma for sigma = 1.15,
%         and jumping with round()). Now ceil(3*sigma), so the truncated Gauss
%         derivatives keep their shape and the kernel size changes smoothly with sigma.

if nargin < 2, sigma = 1; end

% Make kernel coordinates
half    = max(2, ceil(3*sigma));
[X,Y]   = ndgrid(-half:half);

% Build the gaussian 2nd derivatives filters
DGaussx  = 1/(2*pi*sigma^4)*(-X).* exp(-(X.^2 + Y.^2)/(2*sigma^2));
DGaussy  = 1/(2*pi*sigma^4)*(-Y).* exp(-(X.^2 + Y.^2)/(2*sigma^2));
DGaussxx = 1/(2*pi*sigma^4) * (X.^2/sigma^2 - 1) .* exp(-(X.^2 + Y.^2)/(2*sigma^2));
DGaussxy = 1/(2*pi*sigma^6) * (X .* Y)           .* exp(-(X.^2 + Y.^2)/(2*sigma^2));
DGaussyy = 1/(2*pi*sigma^4) * (Y.^2/sigma^2 - 1) .* exp(-(X.^2 + Y.^2)/(2*sigma^2));

Dx = imfilter(I,DGaussx,'conv','replicate');
Dy = imfilter(I,DGaussy,'conv','replicate');
Dxx = imfilter(I,DGaussxx,'conv','replicate');
Dxy = imfilter(I,DGaussxy,'conv','replicate');
Dyy = imfilter(I,DGaussyy,'conv','replicate');

end
