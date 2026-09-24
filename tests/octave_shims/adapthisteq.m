function J = adapthisteq(I, varargin)
%ADAPTHISTEQ Octave shim: contrast-limited adaptive histogram equalisation.
%   Supports 'NumTiles', 'ClipLimit' and 'NBins' with MATLAB's semantics
%   (uniform target distribution, bilinear interpolation between tile maps).
%   Only loaded under GNU Octave.
p = struct('NumTiles', [8 8], 'ClipLimit', 0.01, 'NBins', 256, 'Distribution', 'uniform');
for k = 1:2:numel(varargin)
    p.(varargin{k}) = varargin{k + 1};
end
cls = class(I);
I = double(I);
if ~strcmp(cls, 'double') && ~strcmp(cls, 'single')
    I = I / double(intmax(cls));
end
I = min(max(I, 0), 1);
[H, W] = size(I);
nT = p.NumTiles;
th = ceil(H / nT(1));
tw = ceil(W / nT(2));
% pad (symmetric) so tiles divide the image
Hp = th * nT(1);
Wp = tw * nT(2);
P = padarray(I, [Hp - H, Wp - W], 'symmetric', 'post');
nb = p.NBins;
bins = min(floor(P * nb) + 1, nb);
npix = th * tw;
minClip = ceil(npix / nb);
clip = minClip + round(p.ClipLimit * (npix - minClip));
maps = zeros(nT(1), nT(2), nb);
for r = 1:nT(1)
    for c = 1:nT(2)
        b = bins((r - 1) * th + (1:th), (c - 1) * tw + (1:tw));
        h = accumarray(b(:), 1, [nb 1])';
        % clip and redistribute excess uniformly
        excess = sum(max(h - clip, 0));
        h = min(h, clip) + excess / nb;
        cdf = cumsum(h) / sum(h);
        maps(r, c, :) = reshape(cdf, 1, 1, nb);
    end
end
% bilinear interpolation of tile mappings at pixel positions
yc = ((1:nT(1)) - 0.5) * th;
xc = ((1:nT(2)) - 0.5) * tw;
[X, Y] = meshgrid(1:W, 1:H);
X = X - 0.5;
Y = Y - 0.5;
ry = interp1(yc, 1:nT(1), min(max(Y, yc(1)), yc(end)));
rx = interp1(xc, 1:nT(2), min(max(X, xc(1)), xc(end)));
if nT(1) == 1, ry = ones(size(Y)); end
if nT(2) == 1, rx = ones(size(X)); end
r0 = floor(ry); r1 = min(r0 + 1, nT(1)); wy = ry - r0;
c0 = floor(rx); c1 = min(c0 + 1, nT(2)); wx = rx - c0;
bI = bins(1:H, 1:W);
idx = @(r, c) sub2ind([nT(1) nT(2) nb], r, c, bI);
v00 = maps(idx(r0, c0)); v01 = maps(idx(r0, c1));
v10 = maps(idx(r1, c0)); v11 = maps(idx(r1, c1));
J = (1 - wy) .* ((1 - wx) .* v00 + wx .* v01) + wy .* ((1 - wx) .* v10 + wx .* v11);
if ~strcmp(cls, 'double') && ~strcmp(cls, 'single')
    J = cast(round(J * double(intmax(cls))), cls);
end
end
