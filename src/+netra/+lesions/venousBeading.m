function VB = venousBeading(E, A, HE, NV, cfg)
%VENOUSBEADING Venous calibre irregularity (beading) and IRMA-like anomalies.
%
%   VB = netra.lesions.venousBeading(E, A, HE, NV, cfg)
%
%   Beading. The vessel skeleton is split into segments; for each segment
%   longer than cfg.vb.minSegmentDD and wider than cfg.vb.minWidthDD the
%   calibre profile w(s) is measured with sub-pixel precision as the full
%   width at half maximum of the cross-section, sampled along the local
%   normal at canvas resolution. Veins are the
%   darker half of the major segments (venous blood is less oxygenated and
%   veins are wider). The beading index is the standard deviation of the
%   detrended calibre divided by the mean calibre; a segment is beaded when
%   the index exceeds cfg.vb.beadingIndex and the calibre oscillates
%   periodically (autocorrelation peak > cfg.vb.acfPeak at a lag of 1.5-6
%   calibres) - the "string of sausages" appearance of the 4-2-1 rule.
%
%   IRMA. Intraretinal microvascular abnormalities cannot be separated from
%   flat new vessels in a colour photograph with certainty. They are
%   reported as "IRMA-like" when a microvascular anomaly (neovascular
%   score between 80 % of the NV threshold and the threshold) lies outside
%   the disc zone next to haemorrhages (>= 3 within 1 DD) - the ischaemic
%   context in which IRMA occur. This is deliberately conservative and is
%   shown to the reader as supporting evidence only.
%
%   VB fields: segments (struct), quadrants (list of quadrants with beading),
%   maxIndex, irma (struct: x, y, score, prob, quadrant), irmaQuadrants.

b = cfg.vb;
V = A.vessels;
F = A.frame;
s = V.scale;
DDv = F.pxPerDD * s;
B = V.mask;
skel = bwmorph(B, 'thin', Inf);
dist = double(bwdist(~B));
d = 1 - E.gN;                                   % canvas-resolution darkening
cmap = 1 - netra.util.imscale(E.gN, size(B));

segs = netra.util.skeletonSegments(skel, max(6, round(b.minSegmentDD * DDv)));
info = struct('x', {}, 'y', {}, 'meanWidthDD', {}, 'darkness', {}, 'index', {}, ...
    'acf', {}, 'isVein', {}, 'beaded', {}, 'quadrant', {}, 'r', {}, 'c', {}, 'calibre', {});
for k = 1:numel(segs)
    wd0 = 2 * dist(segs(k).idx) - 1;
    if median(wd0) < b.minWidthDD * DDv || numel(wd0) < 8
        continue
    end
    % sub-pixel calibre: FWHM of the cross-section of d, sampled along the
    % local normal of the (smoothed) centre-line at canvas resolution
    xs = movmean(segs(k).c / s, 5);
    ys = movmean(segs(k).r / s, 5);
    % drop 1.5 calibres at each end: junctions and crossings are not beads
    trim = ceil(1.5 * median(wd0));
    if numel(xs) <= 2 * trim + 8
        continue
    end
    xs = xs(trim + 1:end - trim);
    ys = ys(trim + 1:end - trim);
    segIdx = segs(k).idx(trim + 1:end - trim);
    wd = fwhmProfile(d, xs, ys, median(wd0) / s);
    ok = isfinite(wd);
    if nnz(ok) < 8
        continue
    end
    wd = wd(ok);
    n = numel(wd);
    wmed = median(wd);
    trend = movmean(wd, min(max(3, round(3 * wmed)), n - 1));
    r = movmean(wd, 3) - trend;
    idx = std(r) / max(mean(wd), eps);
    acf = autocorrPeak(r, max(2, round(1.5 * wmed)), min(n - 2, round(6 * wmed)));
    mid = round(n / 2);
    xc = xs(mid);
    yc = ys(mid);
    xi = min(max(round(xc), 1), size(F.quadrant, 2));
    yi = min(max(round(yc), 1), size(F.quadrant, 1));
    info(end + 1) = struct('x', xc, 'y', yc, 'meanWidthDD', mean(wd) / F.pxPerDD, ... %#ok<AGROW>
        'darkness', mean(cmap(segIdx)), 'index', idx, 'acf', acf, 'isVein', false, ...
        'beaded', false, 'quadrant', F.quadrant(yi, xi), 'r', ys, 'c', xs, 'calibre', wd);
end
if ~isempty(info)
    dk = [info.darkness];
    veins = dk >= median(dk);
    for k = 1:numel(info)
        info(k).isVein = veins(k);
        info(k).beaded = veins(k) && info(k).index > b.beadingIndex && info(k).acf > b.acfPeak;
    end
end
VB = struct();
VB.segments = info;
bq = [info([info.beaded]).quadrant];
VB.quadrants = unique(bq(bq > 0));
if isempty(info)
    VB.maxIndex = 0;
else
    VB.maxIndex = max([info([info.isVein]).index, 0]);
end

% --------------------------------------------------------- IRMA-like
irma = struct('x', {}, 'y', {}, 'score', {}, 'prob', {}, 'quadrant', {});
S = NV.scoreMap;
lo = 0.8 * cfg.nv.threshold;
cand = S > lo & S <= cfg.nv.threshold & ~F.zone.disc;
if any(cand(:)) && ~isempty(HE.list)
    L = bwlabel(cand, 8);
    st = regionprops(L, 'Centroid', 'PixelIdxList');
    hx = [HE.list.x];
    hy = [HE.list.y];
    hp = [HE.list.prob] >= 0.5;
    for k = 1:numel(st)
        cc = st(k).Centroid;
        near = hp & hypot(hx - cc(1), hy - cc(2)) <= F.pxPerDD;
        if nnz(near) >= 3
            sc = max(S(st(k).PixelIdxList));
            xi = min(max(round(cc(1)), 1), size(S, 2));
            yi = min(max(round(cc(2)), 1), size(S, 1));
            irma(end + 1) = struct('x', cc(1), 'y', cc(2), 'score', sc, ... %#ok<AGROW>
                'prob', netra.util.sigmoid(sc, 0.9 * cfg.nv.threshold, 0.5), ...
                'quadrant', F.quadrant(yi, xi));
        end
    end
end
VB.irma = irma;
iq = [irma([irma.prob] >= cfg.rules.irmaProb).quadrant];
VB.irmaQuadrants = unique(iq(iq > 0));
end

function w = fwhmProfile(d, xs, ys, wGuess)
% Full width at half maximum of the vessel cross-section at every
% centre-line point (Brinchmann-Hansen style calibre measurement).
n = numel(xs);
tx = gradient(xs(:));
ty = gradient(ys(:));
nrm = hypot(tx, ty) + eps;
nx = -ty ./ nrm;
ny = tx ./ nrm;
R = max(4, 1.6 * wGuess + 3);
u = -R:0.5:R;
X = xs(:) + nx * u;
Y = ys(:) + ny * u;
P = reshape(netra.util.bilinear(d, X(:), Y(:), NaN), n, numel(u));
w = nan(n, 1);
c0 = ceil(numel(u) / 2);
for i = 1:n
    p = P(i, :);
    if any(~isfinite(p))
        continue
    end
    base = min(mean(p(1:3)), mean(p(end - 2:end)));
    [pk, j] = max(p(max(1, c0 - 4):min(end, c0 + 4)));
    j = j + max(1, c0 - 4) - 1;
    half = base + 0.5 * (pk - base);
    if pk - base < 0.02
        continue
    end
    l = find(p(1:j) < half, 1, 'last');
    rr = find(p(j:end) < half, 1, 'first') + j - 1;
    if isempty(l) || isempty(rr)
        continue
    end
    xl = u(l) + (half - p(l)) / (p(l + 1) - p(l) + eps) * 0.5;
    xr = u(rr - 1) + (p(rr - 1) - half) / (p(rr - 1) - p(rr) + eps) * 0.5;
    w(i) = xr - xl;
end
end

function p = autocorrPeak(r, lagMin, lagMax)
r = r(:) - mean(r);
den = sum(r .^ 2);
p = 0;
if den <= eps || lagMax <= lagMin
    return
end
for lag = lagMin:lagMax
    p = max(p, sum(r(1:end - lag) .* r(1 + lag:end)) / den);
end
end
