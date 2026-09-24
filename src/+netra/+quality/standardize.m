function S = standardize(rgb, F, D)
%STANDARDIZE Crop the aperture, centre it and resample to a fixed FOV diameter.
%
%   S = netra.quality.standardize(rgb, F, D) maps the fitted aperture circle
%   F (from netra.quality.fovMask) onto a D x D canvas with the FOV centred
%   and a 2 % margin. Parts of the circle that were outside the original
%   photograph (clipped captures) are zero and excluded from S.mask.
%
%   S fields
%     rgb      D x D x 3 image
%     mask     FOV mask on the canvas (visible, in-aperture pixels)
%     circle   full aperture disc on the canvas (including clipped parts)
%     centre   [x y] FOV centre on the canvas, radius (px)
%     scale    canvas px per original px
%     origin   original (x, y) of canvas pixel (1, 1)
%   Use netra.quality.toOriginal / toCanvas to map coordinates.

[H0, W0, ~] = size(rgb);
margin = 1.02;
scale = D / (2 * F.radius * margin);
% very large photographs (IDRiD: 4288 x 2848) are first reduced by an
% anti-aliased factor so that the crop window stays small in memory
pre = 1;
if scale < 0.5
    pre = 2 * scale;
    rgb = netra.util.imscale(rgb, pre);
    F.mask = imresize(F.mask, [size(rgb, 1) size(rgb, 2)], 'nearest');
    F.centre = (F.centre - 0.5) * pre + 0.5;
    F.radius = F.radius * pre;
    scale = D / (2 * F.radius * margin);
end
[H, W, ~] = size(rgb);
half = F.radius * margin;
x0 = F.centre(1) - half + 0.5 / scale;     % x of canvas pixel centre 1
y0 = F.centre(2) - half + 0.5 / scale;

% crop window in original pixels, padded where it leaves the photograph
c1 = floor(F.centre(1) - half); c2 = ceil(F.centre(1) + half);
r1 = floor(F.centre(2) - half); r2 = ceil(F.centre(2) + half);
win = zeros(r2 - r1 + 1, c2 - c1 + 1, 3);
vis = false(r2 - r1 + 1, c2 - c1 + 1);
rr = max(r1, 1):min(r2, H);
cc = max(c1, 1):min(c2, W);
win(rr - r1 + 1, cc - c1 + 1, :) = rgb(rr, cc, :);
vis(rr - r1 + 1, cc - c1 + 1) = F.mask(rr, cc);

% sample the canvas grid from the window (bilinear, anti-aliased)
if scale < 0.999
    for k = 1:3
        win(:, :, k) = imgaussfilt(win(:, :, k), 0.45 / scale);
    end
end
[Xc, Yc] = meshgrid(1:D, 1:D);
xo = x0 + (Xc - 1) / scale - c1 + 1;       % window coordinates
yo = y0 + (Yc - 1) / scale - r1 + 1;
out = zeros(D, D, 3);
for k = 1:3
    out(:, :, k) = interp2(win(:, :, k), xo, yo, 'linear', 0);
end
visC = interp2(double(vis), xo, yo, 'linear', 0) > 0.5;

ctr = [(F.centre(1) - x0) * scale + 1, (F.centre(2) - y0) * scale + 1];
rad = F.radius * scale;
circle = (Xc - ctr(1)) .^ 2 + (Yc - ctr(2)) .^ 2 <= rad ^ 2;

S = struct();
S.rgb = min(max(out, 0), 1);
S.mask = visC & circle;
S.circle = circle;
S.centre = ctr;
S.radius = rad;
% report the mapping relative to the photograph as supplied
S.scale = scale * pre;
S.origin = ([x0 y0] - 0.5) / pre + 0.5;
S.size = [H0 W0];
S.coverage = nnz(S.mask) / max(nnz(circle), 1);
end
