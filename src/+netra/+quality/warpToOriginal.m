function I = warpToOriginal(C, S, method)
%WARPTOORIGINAL Resample a canvas map back onto the photograph's pixel grid.
%   I = netra.quality.warpToOriginal(C, S) - used to score segmentations at
%   the native resolution of a benchmark (e.g. DRIVE 565 x 584).
if nargin < 3
    if islogical(C), method = 'nearest'; else, method = 'linear'; end
end
H = S.size(1);
W = S.size(2);
[Xo, Yo] = meshgrid(1:W, 1:H);
xc = (Xo - S.origin(1)) * S.scale + 1;
yc = (Yo - S.origin(2)) * S.scale + 1;
I = zeros(H, W, size(C, 3));
for k = 1:size(C, 3)
    I(:, :, k) = interp2(double(C(:, :, k)), xc, yc, method, 0);
end
if islogical(C)
    I = I > 0.5;
end
end
