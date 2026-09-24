function F = fovMask(rgb)
%FOVMASK Locate the circular camera aperture (field of view) of a fundus image.
%
%   F = netra.quality.fovMask(rgb) returns
%     mask      logical FOV mask at full resolution
%     centre    [x y] of the fitted aperture circle (px)
%     radius    aperture radius (px) - valid even when the circle is clipped
%     coverage  visible fraction of the aperture disc (1 = complete)
%     clipped   struct with logical top/bottom/left/right
%     ok        false when no plausible aperture was found
%
%   The aperture is thresholded on the brightest channel at 35 % of Otsu's
%   level (above the measured background floor), then a circle is fitted
%   robustly to the boundary points that do not lie on the image frame.
%   This recovers the true radius for IDRiD/APTOS-style crops where the top
%   and bottom of the circle are cut off, and ignores camera notches.

[H, W, ~] = size(rgb);
s = min(1, 512 / max(H, W));
small = netra.util.imscale(rgb, s);
v = max(small, [], 3);
v = medfilt2(v, [5 5], 'symmetric');
floorLvl = netra.util.pct(v(:), 3);
[~, bgSigma] = netra.util.robustStats(v(v <= netra.util.pct(v(:), 10)));
t = graythresh(v);
thr = max([0.35 * t, floorLvl + 6 * bgSigma, 0.02]);
m = v > thr;
m = imopen(m, strel('disk', 2, 0));
m = imfill(m, 'holes');
m = largestComponent(m);

F = struct('mask', false(H, W), 'centre', [W H] / 2, 'radius', min(H, W) / 2, ...
    'coverage', 0, 'clipped', struct('top', false, 'bottom', false, 'left', false, ...
    'right', false), 'ok', false);
if nnz(m) < 0.05 * numel(m)
    return
end

[h, w] = size(m);
per = bwperim(m);
edgeBand = false(h, w);
edgeBand([1:2, h - 1:h], :) = true;
edgeBand(:, [1:2, w - 1:w]) = true;
per = per & ~edgeBand;
[py, px] = find(per);
if numel(px) >= 40
    [c, r] = netra.util.circleFit(px, py);
else
    % aperture fills the frame: fall back to the bounding box
    st = regionprops(m, 'BoundingBox');
    bb = st(1).BoundingBox;
    c = [bb(1) + bb(3) / 2, bb(2) + bb(4) / 2];
    r = max(bb(3), bb(4)) / 2;
end
% back to full-resolution coordinates (pixel centres)
c = (c - 0.5) / s + 0.5;
r = r / s;

[X, Y] = meshgrid(1:W, 1:H);
circle = (X - c(1)) .^ 2 + (Y - c(2)) .^ 2 <= (0.995 * r) ^ 2;
mFull = imresize(m, [H W], 'nearest');
mFull = imclose(mFull, strel('disk', max(2, round(4 / s)), 0));
mask = circle & mFull;

F.mask = mask;
F.centre = c;
F.radius = r;
F.coverage = nnz(mask) / (pi * r ^ 2);
F.clipped = struct('top', c(2) - r < 0.5, 'bottom', c(2) + r > H + 0.5, ...
    'left', c(1) - r < 0.5, 'right', c(1) + r > W + 0.5);
F.ok = r > 0.2 * min(H, W) && F.coverage > 0.2;
end

function m = largestComponent(m)
L = bwlabel(m, 8);
if max(L(:)) <= 1
    return
end
a = accumarray(L(L > 0), 1);
[~, k] = max(a);
m = L == k;
end
