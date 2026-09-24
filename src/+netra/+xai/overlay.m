function img = overlay(base, A, L, varargin)
%OVERLAY Annotated fundus: anatomy, ETDRS grid and every lesion, drawn in pixels.
%
%   img = netra.xai.overlay(base, A, L) draws on the canvas image BASE
%   (usually E.display) with anti-aliased primitives, so the result is a
%   plain RGB array that looks the same in MATLAB, Octave, a PDF or a PNG
%   sent over a 2G link.
%
%     disc        dashed white ring;  fovea: small white cross
%     ETDRS grid  rings at 1/3, 1 and 2 DD around the fovea + quadrant axes
%     MA          crimson ring at the sub-pixel centre (ring, not dot, so
%                 the lesion itself stays visible under the marker)
%     haemorrhage outline, colour by morphology (dot/blot violet, flame
%                 indigo, pre-retinal deep purple)
%     exudate     yellow outline;  cotton-wool spot: ice-blue outline
%     NV          acid-green box;  IRMA-like: teal ring;  beaded vein:
%                 orange trace along the vessel
%
%   Options: 'Grid' (true), 'MinProb' (0.5), 'Layers' (cellstr subset of
%   {'anatomy','ma','he','ex','cws','nv','vb','irma'}).

o = netra.util.opts(struct('Grid', true, 'MinProb', 0.5, ...
    'Layers', {{'anatomy', 'ma', 'he', 'ex', 'cws', 'nv', 'vb', 'irma'}}), varargin{:});
P = netra.util.palette();
img = base;
F = A.frame;
D = size(img, 1);
DD = F.pxPerDD;
lw = max(1, D / 700);
on = @(name) any(strcmp(o.Layers, name));

if on('anatomy')
    if o.Grid
        for rDD = [1 / 3, 1, 2]
            img = ring(img, F.fovea, rDD * DD, [1 1 1], 0.35, 0.8 * lw, false);
        end
        for k = 0:1
            ax = F.nasal * (1 - k) + F.superior * k;
            img = segment(img, F.fovea - 2 * DD * ax, F.fovea - DD / 3 * ax, [1 1 1], 0.3, 0.8 * lw);
            img = segment(img, F.fovea + DD / 3 * ax, F.fovea + 2 * DD * ax, [1 1 1], 0.3, 0.8 * lw);
        end
    end
    img = ring(img, A.od.centre, A.od.radius, P.od, 0.85, 1.2 * lw, true);
    c = F.fovea;
    img = segment(img, c - [6 0] * lw, c + [6 0] * lw, P.fovea, 0.9, lw);
    img = segment(img, c - [0 6] * lw, c + [0 6] * lw, P.fovea, 0.9, lw);
end

if on('he') && ~isempty(L.he.list)
    lab = bwlabel(L.he.mask, 8);
    for i = 1:numel(L.he.list)
        h = L.he.list(i);
        if h.prob < o.MinProb, continue; end
        switch h.type
            case 'flame', col = P.flame;
            case 'preretinal', col = P.preret;
            otherwise, col = P.blot;
        end
        yi = min(max(round(h.y), 1), D);
        xi = min(max(round(h.x), 1), D);
        k = lab(yi, xi);
        if k > 0
            img = contour(img, lab == k, col, 0.95, lw);
        else
            img = ring(img, [h.x h.y], max(3, sqrt(h.areaPx / pi) + 2), col, 0.95, lw, false);
        end
    end
end
if on('ex') && any(L.ex.mask(:))
    img = contour(img, L.ex.mask, P.exudate, 0.95, lw);
end
if on('cws') && any(L.ex.cwsMask(:))
    img = contour(img, L.ex.cwsMask, P.cws, 0.95, 1.2 * lw);
end
if on('ma')
    for i = 1:numel(L.ma.list)
        m = L.ma.list(i);
        if m.prob < o.MinProb || ~strcmp(m.class, 'MA'), continue; end
        img = ring(img, [m.x m.y], max(4 * lw, 2.5 * m.sigmaPx + 3), P.ma, 0.95, lw, false);
    end
end
if on('vb')
    for i = 1:numel(L.vb.segments)
        s = L.vb.segments(i);
        if ~s.beaded, continue; end
        for j = 1:3:numel(s.c) - 3
            img = segment(img, [s.c(j) s.r(j)], [s.c(j + 3) s.r(j + 3)], P.vb, 0.9, 1.5 * lw);
        end
    end
end
if on('irma')
    for i = 1:numel(L.vb.irma)
        q = L.vb.irma(i);
        if q.prob < o.MinProb, continue; end
        img = ring(img, [q.x q.y], 0.3 * DD, P.irma, 0.9, 1.2 * lw, true);
    end
end
if on('nv')
    for i = 1:numel(L.nv.candidates)
        c = L.nv.candidates(i);
        if c.prob < o.MinProb, continue; end
        b = c.bbox;
        pad = 0.05 * DD;
        p1 = [b(1) - pad, b(2) - pad];
        p2 = [b(1) + b(3) + pad, b(2) + b(4) + pad];
        img = segment(img, p1, [p2(1) p1(2)], P.nv, 0.95, 1.5 * lw);
        img = segment(img, [p2(1) p1(2)], p2, P.nv, 0.95, 1.5 * lw);
        img = segment(img, p2, [p1(1) p2(2)], P.nv, 0.95, 1.5 * lw);
        img = segment(img, [p1(1) p2(2)], p1, P.nv, 0.95, 1.5 * lw);
    end
end
img = min(max(img, 0), 1);
end

% ======================================================================
function img = blend(img, cov, col, alpha)
for k = 1:3
    img(:, :, k) = img(:, :, k) .* (1 - alpha * cov) + col(k) * alpha * cov;
end
end

function img = ring(img, c, r, col, alpha, w, dashed)
D = size(img, 1);
R = r + w + 2;
x1 = max(1, floor(c(1) - R)); x2 = min(D, ceil(c(1) + R));
y1 = max(1, floor(c(2) - R)); y2 = min(D, ceil(c(2) + R));
if x1 > x2 || y1 > y2, return; end
[X, Y] = meshgrid(x1:x2, y1:y2);
d = abs(hypot(X - c(1), Y - c(2)) - r);
cov = max(0, min(1, w / 2 + 0.5 - d));
if dashed
    ang = atan2(Y - c(2), X - c(1));
    cov = cov .* (mod(ang * max(r, 1) / 6, 2 * pi) < pi);
end
sub = img(y1:y2, x1:x2, :);
img(y1:y2, x1:x2, :) = blend(sub, cov, col, alpha);
end

function img = segment(img, p, q, col, alpha, w)
D = size(img, 1);
R = w + 2;
x1 = max(1, floor(min(p(1), q(1)) - R)); x2 = min(D, ceil(max(p(1), q(1)) + R));
y1 = max(1, floor(min(p(2), q(2)) - R)); y2 = min(D, ceil(max(p(2), q(2)) + R));
if x1 > x2 || y1 > y2, return; end
[X, Y] = meshgrid(x1:x2, y1:y2);
v = q - p;
L2 = max(sum(v .^ 2), eps);
t = min(max(((X - p(1)) * v(1) + (Y - p(2)) * v(2)) / L2, 0), 1);
d = hypot(X - (p(1) + t * v(1)), Y - (p(2) + t * v(2)));
cov = max(0, min(1, w / 2 + 0.5 - d));
sub = img(y1:y2, x1:x2, :);
img(y1:y2, x1:x2, :) = blend(sub, cov, col, alpha);
end

function img = contour(img, mask, col, alpha, w)
edge = mask & ~imerode(mask, true(3));
if w > 1.5
    edge = imdilate(edge, strel('disk', round(w / 2), 0));
end
img = blend(img, double(edge), col, alpha);
end
