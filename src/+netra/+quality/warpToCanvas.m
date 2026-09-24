function C = warpToCanvas(I, S, method)
%WARPTOCANVAS Resample a photograph-space image or mask onto the canvas of S.
%   C = netra.quality.warpToCanvas(I, S) uses bilinear interpolation;
%   logical inputs use nearest-neighbour and stay logical. Use it to bring
%   ground-truth masks (DRIVE vessels, IDRiD lesions) into analysis space.
if nargin < 3
    if islogical(I), method = 'nearest'; else, method = 'linear'; end
end
D = size(S.mask, 1);
[Xc, Yc] = meshgrid(1:D, 1:D);
xo = (Xc - 1) / S.scale + S.origin(1);
yo = (Yc - 1) / S.scale + S.origin(2);
C = zeros(D, D, size(I, 3));
for k = 1:size(I, 3)
    C(:, :, k) = interp2(double(I(:, :, k)), xo, yo, method, 0);
end
if islogical(I)
    C = C > 0.5;
end
end
