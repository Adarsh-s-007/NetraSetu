function OD = opticDisc(E, V, S, cfg)
%OPTICDISC Locate and measure the optic disc.
%
%   OD = netra.anatomy.opticDisc(E, V, S, cfg) combines three cues, each a
%   robust z-score over the field of view:
%     brightness  disc-scale bright blob in the colour-normalised image
%                 (difference of Gaussians at DD/8 and DD)
%     calibre     density of major (thick) vessels - they all enter the disc
%     vertical    density of vertically running vessels in a tall, narrow
%                 window: the superior and inferior arcades leave the disc
%                 vertically, which no bright lesion mimics
%     convergence votes cast along the direction of every major vessel;
%                 all trunks point at the disc
%   plus a mild prior that the disc lies near the horizontal midline.
%   The best candidate is refined inside a 1.7 DD window: vessels are
%   removed by a grey-level closing, the disc is thresholded (Otsu) and a
%   circle is fitted to its boundary. The measured diameter becomes the
%   patient's own disc diameter (DD), the unit of every clinical rule.
%
%   OD fields (canvas coordinates): centre [x y], radius, pxPerDD,
%   confidence (0..1), mask, measured (true if the refinement succeeded),
%   cues (score maps at anatomy resolution, for explanation).

D = size(E.gN, 1);
Da = round(cfg.scale.anatomyDiameter * 1.02);
f = Da / D;
DDprior = cfg.scale.ddPerFOV * 2 * S.radius;          % canvas px
DDa = DDprior * f;                                      % anatomy px

rgbN = netra.util.imscale(E.rgbN, [Da Da]);
m = imresize(E.mask, [Da Da], 'nearest');
[Xa, Ya] = meshgrid(1:Da, 1:Da);
ca = (S.centre - 0.5) * f + 0.5;
ra = S.radius * f;
rr = hypot(Xa - ca(1), Ya - ca(2)) / ra;
valid = m & rr <= cfg.od.maxRadiusFOV;

lum = 0.30 * rgbN(:, :, 1) + 0.59 * rgbN(:, :, 2) + 0.11 * rgbN(:, :, 3);
lumF = netra.util.fillOutside(lum, m, 2);
bright = netra.util.smooth(lumF, DDa / 8) - netra.util.smooth(lumF, DDa);

vmask = imresize(double(V.mask), [Da Da], 'bilinear');
vthick = imresize(double(V.thick), [Da Da], 'bilinear');
th = imresize(V.theta, [Da Da], 'nearest');
calibre = netra.util.smooth(vthick, DDa / 3);
vertical = netra.util.gauss2(vmask .* abs(sin(th)), 0.55 * DDa, 0.12 * DDa);

converge = convergence(V, Da, DDa);

zb = robustZ(bright, valid);
zc = robustZ(calibre, valid);
zv = robustZ(vertical, valid);
zg = robustZ(converge, valid);
% discs of macula- and disc-centred fields lie near the horizontal midline
prior = -0.5 * ((Ya - ca(2)) / (0.45 * ra)) .^ 2;
% capped cues; vessel cues only count where the fundus is bright, because
% haemorrhage clusters can mimic dense, thick "vessels" but are never bright
cap = @(z) min(z, 5);
gate = netra.util.sigmoid(zb, 0.5, 0.5);
score = cfg.od.wBrightness * cap(zb) + gate .* (cfg.od.wThickVessels * cap(zc) + ...
    cfg.od.wVertical * cap(zv) + cfg.od.wConvergence * cap(zg)) + prior;
score(~valid) = -Inf;

% two best, well separated candidates
[s1, i1] = max(score(:));
[y1, x1] = ind2sub([Da Da], i1);
away = hypot(Xa - x1, Ya - y1) > 1.5 * DDa;
s2 = max(score(away & valid));
if isempty(s2) || ~isfinite(s2)
    s2 = s1 - 3;
end

% ------------------------------------------------------------ refinement
[cRef, rRef, ok] = refine(lum, m, [x1 y1], DDa, cfg);
radiusPrior = DDa / 2;
if ok && rRef > (1 - cfg.scale.ddTolerance) * radiusPrior && ...
        rRef < (1 + cfg.scale.ddTolerance) * radiusPrior && norm(cRef - [x1 y1]) < 0.6 * DDa
    centreA = cRef;
    radiusA = rRef;
    measured = true;
else
    centreA = [x1 y1];
    radiusA = radiusPrior;
    measured = false;
end

margin = s1 - s2;
conf = netra.util.sigmoid(margin, 1.0, 0.5) * netra.util.sigmoid(s1, 6.0, 1.2);
if ~measured
    conf = 0.8 * conf;
end

OD = struct();
OD.centre = (centreA - 0.5) / f + 0.5;
OD.radius = radiusA / f;
w = 0.7 * conf * measured;
OD.pxPerDD = exp(w * log(2 * OD.radius) + (1 - w) * log(DDprior));
OD.confidence = conf;
OD.measured = measured;
OD.score = s1;
OD.margin = margin;
[Xc, Yc] = meshgrid(1:D, 1:D);
OD.mask = hypot(Xc - OD.centre(1), Yc - OD.centre(2)) <= OD.radius;
OD.cues = struct('brightness', zb, 'calibre', zc, 'vertical', zv, 'convergence', zg, ...
    'score', score, 'scale', f);
end

% ======================================================================
function A = convergence(V, Da, DDa)
% Every major-vessel centre-line pixel votes along its own direction for
% points up to 2.2 DD away; the disc collects votes from all trunks (a
% line-based analogue of Hoover & Goldbaum's fuzzy convergence).
skel = bwmorph(V.mask, 'thin', Inf);
wid = 2 * double(bwdist(~V.mask)) - 1;
Dv = size(V.mask, 1);
DDv = DDa * Dv / Da;
sel = skel & wid >= 0.035 * DDv;
[yy, xx] = find(sel);
A = zeros(Da);
if numel(xx) < 10
    return
end
if numel(xx) > 4000
    keep = round(linspace(1, numel(xx), 4000));
    yy = yy(keep); xx = xx(keep);
end
th = V.theta(sub2ind([Dv Dv], yy, xx));
f = Da / Dv;
t = linspace(-2.2 * DDa, 2.2 * DDa, 90);
X = (xx - 0.5) * f + 0.5 + cos(th) * t;
Y = (yy - 0.5) * f + 0.5 + sin(th) * t;
ok = X >= 1 & Y >= 1 & X <= Da & Y <= Da;
idx = sub2ind([Da Da], round(Y(ok)), round(X(ok)));
A = reshape(accumarray(idx(:), 1, [Da * Da 1]), Da, Da);
A = netra.util.smooth(A, 0.25 * DDa);
end

function z = robustZ(x, m)
[med, s] = netra.util.robustStats(x(m));
z = (x - med) / s;
end

function [c, r, ok] = refine(lum, m, p, DDa, cfg)
% threshold the vessel-free disc inside a local window and fit a circle
ok = false;
c = p;
r = NaN;
half = round(cfg.od.refineWindowDD * DDa / 2);
[H, W] = size(lum);
r1 = max(1, round(p(2)) - half); r2 = min(H, round(p(2)) + half);
c1 = max(1, round(p(1)) - half); c2 = min(W, round(p(1)) + half);
win = lum(r1:r2, c1:c2);
mw = m(r1:r2, c1:c2);
if nnz(mw) < 0.5 * numel(mw)
    return
end
closed = imclose(win, strel('disk', max(2, round(0.12 * DDa)), 0));
closed = imgaussfilt(closed, max(1, 0.04 * DDa));
v = closed(mw);
lo = min(v);
hi = max(v);
if hi - lo < eps
    return
end
t = netra.util.otsu((v - lo) / (hi - lo)) * (hi - lo) + lo;
B = closed > t & mw;
B = imopen(B, strel('disk', max(1, round(0.06 * DDa)), 0));
L = bwlabel(B, 8);
if max(L(:)) == 0
    return
end
pl = [round(p(2)) - r1 + 1, round(p(1)) - c1 + 1];
pl = min(max(pl, 1), size(L));
k = L(pl(1), pl(2));
if k == 0
    st = regionprops(L, 'Centroid', 'Area');
    cen = reshape([st.Centroid], 2, [])';
    [~, k] = min(hypot(cen(:, 1) - pl(2), cen(:, 2) - pl(1)));
end
blob = imfill(L == k, 'holes');
per = bwperim(blob);
[py, px] = find(per);
if numel(px) < 12
    return
end
[cc, rr] = netra.util.circleFit(px, py);
st = regionprops(blob, 'Solidity');
if st(1).Solidity < 0.75
    return
end
c = [cc(1) + c1 - 1, cc(2) + r1 - 1];
r = rr;
ok = isfinite(r);
end
