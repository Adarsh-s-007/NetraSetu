function [rgb, gt] = degrade(rgb, gt, spec)
%DEGRADE Reproduce the capture failures seen with portable fundus cameras.
%
%   [rgb, gt] = netra.phantom.degrade(rgb, gt, spec) applies, in optical
%   order, any subset of:
%     haze      0..1  media opacity / dirty lens: veiling glare + contrast loss
%     blur      px    defocus (sigma, expressed at the 1024-px FOV scale)
%     vignette  0..1  extra radial fall-off (small, undilated pupil)
%     lash      0..1  fraction of the FOV height shadowed by lid and lashes
%     flare     0..1  corneal reflection arc near the FOV rim
%     exposure  gain  global exposure (<1 dark, >1 saturating)
%     noise     sigma additional sensor noise
%     shift     [dx dy] FOV decentration as a fraction of the FOV radius
%     crop      0..1  fraction of FOV height cut away (top + bottom)
%     jpeg      1..100 JPEG re-compression quality
%
%   gt is updated (FOV mask, coordinates, gradable flag, list of issues) so
%   that quality-assessment tests know what a competent grader would say.

N = size(rgb, 1);
R = gt.fovRadius;
c = gt.fovCentre;
[X, Y] = meshgrid(1:size(rgb, 2), 1:N);
r = hypot(X - c(1), Y - c(2));
inF = gt.fov;
s = R / 481;                                   % px scale relative to a 1024 canvas
par = @(name, def) fieldOr(spec, name, def);

issues = {};
borderline = {};

h = par('haze', 0);
if h > 0
    veil = [0.66 0.50 0.40];
    for k = 1:3
        ch = rgb(:, :, k);
        glow = imgaussfilt(ch, 0.12 * N);
        ch(inF) = (1 - h) * ch(inF) + h * (0.5 * glow(inF) + 0.5 * veil(k));
        rgb(:, :, k) = ch;
    end
    if h >= 0.55, issues{end + 1} = 'contrast'; elseif h >= 0.3, borderline{end + 1} = 'contrast'; end
end

b = par('blur', 0);
if b > 0
    for k = 1:3
        rgb(:, :, k) = imgaussfilt(rgb(:, :, k), b * s);
    end
    if b >= 3.0, issues{end + 1} = 'blur'; elseif b >= 1.5, borderline{end + 1} = 'blur'; end
end

v = par('vignette', 0);
if v > 0
    fall = max(0.05, 1 - v * (r / R) .^ 2);
    rgb = rgb .* repmat(fall, [1 1 3]);
    if v >= 0.85, issues{end + 1} = 'dark'; end
end

l = par('lash', 0);
if l > 0
    edgeY = c(2) - R + l * 2 * R + 0.04 * R * sin(X / (0.07 * R));
    streak = 0.85 + 0.15 * sin(X / 3.1) .* sin(X / 7.7);
    shade = 0.12 + 0.88 ./ (1 + exp(-(Y - edgeY) / (0.03 * R)));
    shade = min(1, shade .* streak + (Y > edgeY + 0.1 * R));
    rgb = rgb .* repmat(shade, [1 1 3]);
    if l >= 0.35, issues{end + 1} = 'artifact'; elseif l >= 0.15, borderline{end + 1} = 'artifact'; end
end

f = par('flare', 0);
if f > 0
    ang = atan2(Y - c(2), X - c(1));
    a0 = 2 * pi * rand;
    arc = exp(-(r - 0.88 * R) .^ 2 / (2 * (0.05 * R) ^ 2)) .* ...
        exp(-(mod(ang - a0 + pi, 2 * pi) - pi) .^ 2 / (2 * 0.5 ^ 2));
    tint = [0.95 0.92 0.88];
    for k = 1:3
        rgb(:, :, k) = rgb(:, :, k) + f * tint(k) * arc .* inF;
    end
    if f >= 0.8, issues{end + 1} = 'artifact'; elseif f >= 0.4, borderline{end + 1} = 'artifact'; end
end

e = par('exposure', 1);
if e ~= 1
    rgb = rgb * e;
    if e <= 0.35, issues{end + 1} = 'dark'; elseif e <= 0.6, borderline{end + 1} = 'dark'; end
    if e >= 3.0, issues{end + 1} = 'bright'; elseif e >= 2.0, borderline{end + 1} = 'bright'; end
end

n = par('noise', 0);
if n > 0
    rgb = rgb + n * randn(size(rgb)) .* repmat(inF, [1 1 3]);
    if n >= 0.06, issues{end + 1} = 'noise'; elseif n >= 0.03, borderline{end + 1} = 'noise'; end
end
rgb = min(max(rgb, 0), 1);

sh = par('shift', [0 0]);
if any(sh ~= 0)
    d = round(sh * R);
    [rgb, gt] = translate(rgb, gt, d);
end

cr = par('crop', 0);
if cr > 0
    keep = round(c(2) - (1 - cr / 2) * R):round(c(2) + (1 - cr / 2) * R);
    keep = keep(keep >= 1 & keep <= size(rgb, 1));
    [rgb, gt] = cropRows(rgb, gt, keep);
end

q = par('jpeg', 0);
if q > 0
    tmp = [tempname() '.jpg'];
    imwrite(im2uint8(rgb), tmp, 'Quality', q);
    rgb = double(imread(tmp)) / 255;
    delete(tmp);
end
rgb = round(rgb * 255) / 255;

coverage = nnz(gt.fov) / (pi * gt.fovRadius ^ 2);
if coverage < 0.55
    issues{end + 1} = 'field';
elseif coverage < 0.75
    borderline{end + 1} = 'field';
end
gt.coverage = coverage;
gt.issues = unique([gt.issues, issues]);
gt.borderline = unique(borderline);
gt.gradable = isempty(gt.issues);
gt.degradation = spec;
end

% ----------------------------------------------------------------------
function v = fieldOr(s, name, def)
if isfield(s, name)
    v = s.(name);
else
    v = def;
end
end

function [rgb, gt] = translate(rgb, gt, d)
[H, W, ~] = size(rgb);
out = zeros(size(rgb));
outF = false(H, W);
rs = max(1, 1 + d(2)):min(H, H + d(2));
cs = max(1, 1 + d(1)):min(W, W + d(1));
out(rs, cs, :) = rgb(rs - d(2), cs - d(1), :);
outF(rs, cs) = gt.fov(rs - d(2), cs - d(1));
rgb = out + 0.012 * repmat(~outF, [1 1 3]);
gt.fov = outF;
gt = moveCoords(gt, d);
masks = {'vessels', 'arteries', 'vesselWidth', 'maMask', 'heMask', 'exMask', 'cwsMask', 'nvMask', 'irmaMask'};
for k = 1:numel(masks)
    if isfield(gt, masks{k})
        m = gt.(masks{k});
        o = zeros(size(m), class(m));
        o(rs, cs) = m(rs - d(2), cs - d(1));
        gt.(masks{k}) = o;
    end
end
end

function [rgb, gt] = cropRows(rgb, gt, keep)
rgb = rgb(keep, :, :);
masks = {'fov', 'vessels', 'arteries', 'vesselWidth', 'maMask', 'heMask', 'exMask', ...
    'cwsMask', 'nvMask', 'irmaMask'};
for k = 1:numel(masks)
    if isfield(gt, masks{k})
        gt.(masks{k}) = gt.(masks{k})(keep, :);
    end
end
gt = moveCoords(gt, [0, -(keep(1) - 1)]);
end

function gt = moveCoords(gt, d)
gt.fovCentre = gt.fovCentre + d;
gt.od = gt.od + d;
gt.fovea = gt.fovea + d;
for i = 1:numel(gt.ma)
    gt.ma(i).x = gt.ma(i).x + d(1);
    gt.ma(i).y = gt.ma(i).y + d(2);
end
for i = 1:numel(gt.he)
    gt.he(i).x = gt.he(i).x + d(1);
    gt.he(i).y = gt.he(i).y + d(2);
end
end
