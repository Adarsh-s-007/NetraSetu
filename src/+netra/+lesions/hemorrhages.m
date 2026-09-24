function HE = hemorrhages(E, A, MA, cfg)
%HEMORRHAGES Detect intraretinal haemorrhages and classify their morphology.
%
%   HE = netra.lesions.hemorrhages(E, A, MA, cfg)
%
%   After removing the smooth foveal depression (netra.lesions.foveaCompensate),
%   dark regions of the darkening image d = 1 - gN above an adaptive level
%   (max(cfg.he.minDarkening, median + k robust sigma)) are opened with a
%   disc of ~60 um radius, which removes every vessel narrower than ~120 um
%   but keeps haemorrhages; long major-vessel trunks are subtracted. Round
%   red dots between 125 and 250 um found by the microaneurysm stage are
%   added as dot haemorrhages.
%
%   Morphology follows the clinical description of where the blood lies:
%     dot         <= 250 um, round (deep, inner nuclear layer)
%     blot        larger, irregular (deeper retina)
%     flame       elongated along the nerve-fibre direction, i.e. radially
%                 from the disc (superficial nerve-fibre layer)
%     preretinal  >= cfg.he.preretinalDA disc areas and very dark - a PDR sign
%   The nerve-fibre direction is approximated by the radial direction from
%   the disc centre; alignment = |cos(long axis - radial direction)|.
%
%   HE.list fields: x, y, type, areaPx, areaDA, eqDiamUm, majorUm, ecc,
%   solidity, alignment, contrast, redness, prob, quadrant, distFoveaDD.
%   HE.mask, HE.counts (per type), HE.perQuadrant (dot+blot+flame, prob >= 0.5).

h = cfg.he;
F = A.frame;
D = size(E.gN, 1);
DD = F.pxPerDD;
umPx = F.umPerPx;
mask = E.mask & F.distDisc > 0.65 & ...
    imerode(E.mask, strel('disk', max(2, round(0.06 * DD)), 0));

d = 1 - E.gN;
d(~E.mask) = 0;
d = imgaussfilt(d, 0.7);
d = netra.lesions.foveaCompensate(d, F, E.mask);
bg = mask & ~A.vessels.maskWork;
[med, rs] = netra.util.robustStats(d(bg));
T = max(h.minDarkening, med + h.thresholdK * rs);
C = d > T & mask;
rOpen = max(1, round(h.openRadiusUm / umPx));
C = imopen(C, strel('disk', rOpen, 0));
% subtract long major vessels (dilated by one pixel)
C = C & ~imdilate(A.vessels.thickWork, true(3));
C = imopen(C, strel('disk', max(1, rOpen - 1), 0));
minArea = max(6, round(pi / 4 * (h.minAreaUm2 ^ 0.5 / umPx) ^ 2 * 0.8));
C = bwareaopen(C, minArea);

L = bwlabel(C, 8);
st = regionprops(L, 'Area', 'Centroid', 'Eccentricity', 'Solidity', ...
    'MajorAxisLength', 'MinorAxisLength', 'PixelIdxList');
list = repmat(emptyEntry(), 0, 1);
DA = pi / 4 * DD ^ 2;                                  % one disc area in px
rgbN = E.rgbN;
t = cfg.enhance.targetRGB;
R = rgbN(:, :, 1) / t(1);
G = rgbN(:, :, 2) / t(2);
sg = @netra.util.sigmoid;
for k = 1:numel(st)
    pix = st(k).PixelIdxList;
    [yy, xx] = ind2sub([D D], pix);
    c = st(k).Centroid;
    e = emptyEntry();
    e.x = c(1);
    e.y = c(2);
    e.areaPx = st(k).Area;
    e.areaDA = st(k).Area / DA;
    e.eqDiamUm = 2 * sqrt(st(k).Area / pi) * umPx;
    e.majorUm = st(k).MajorAxisLength * umPx;
    e.ecc = st(k).Eccentricity;
    e.solidity = st(k).Solidity;
    % long-axis direction from second moments (x right, y down)
    mx = mean(xx); my = mean(yy);
    mu20 = mean((xx - mx) .^ 2); mu02 = mean((yy - my) .^ 2); mu11 = mean((xx - mx) .* (yy - my));
    theta = 0.5 * atan2(2 * mu11, mu20 - mu02);
    radial = atan2(my - F.od(2), mx - F.od(1));
    e.alignment = abs(cos(theta - radial));
    e.contrast = mean(d(pix));
    ring = ringPixels(L, k, xx, yy, D);
    dR = max(median(R(ring)) - mean(R(pix)), 0);
    dG = max(median(G(ring)) - mean(G(pix)), 1e-3);
    e.redness = min(dR / dG, 2);
    yi = min(max(round(my), 1), D);
    xi = min(max(round(mx), 1), D);
    e.quadrant = F.quadrant(yi, xi);
    e.distFoveaDD = F.distFovea(yi, xi);
    e.type = classify(e, h);
    e.prob = sg((e.contrast - T) / max(rs, 1e-3), 1.5, 0.8) * sg(0.85 - e.redness, 0, 0.12) * ...
        sg(e.solidity, 0.45, 0.08);
    list(end + 1, 1) = e; %#ok<AGROW>
end

% dot haemorrhages from the microaneurysm stage (125-250 um red dots)
for i = 1:numel(MA.list)
    m = MA.list(i);
    if ~strcmp(m.class, 'dot') || m.prob < 0.5
        continue
    end
    yi = min(max(round(m.y), 1), D);
    xi = min(max(round(m.x), 1), D);
    if L(yi, xi) > 0
        continue                                      % already a component
    end
    e = emptyEntry();
    e.x = m.x; e.y = m.y;
    e.areaPx = pi * (1.1774 * m.sigmaPx) ^ 2;
    e.areaDA = e.areaPx / DA;
    e.eqDiamUm = m.diameterUm;
    e.majorUm = m.diameterUm;
    e.ecc = 0;
    e.solidity = 1;
    e.alignment = 0;
    e.contrast = m.amplitude;
    e.redness = m.redness;
    e.quadrant = m.quadrant;
    e.distFoveaDD = m.distFoveaDD;
    e.type = 'dot';
    e.prob = m.prob;
    list(end + 1, 1) = e; %#ok<AGROW>
end

HE = struct();
HE.list = list;
HE.threshold = T;
HE.mask = C;
types = {'dot', 'blot', 'flame', 'preretinal'};
HE.counts = struct();
for j = 1:numel(types)
    HE.counts.(types{j}) = sum(strcmp({list.type}, types{j}) & [list.prob] >= 0.5);
end
HE.perQuadrant = zeros(1, 4);
for i = 1:numel(list)
    if list(i).prob >= 0.5 && ~strcmp(list(i).type, 'preretinal') && list(i).quadrant > 0
        HE.perQuadrant(list(i).quadrant) = HE.perQuadrant(list(i).quadrant) + 1;
    end
end
end

% ======================================================================
function e = emptyEntry()
e = struct('x', 0, 'y', 0, 'type', 'blot', 'areaPx', 0, 'areaDA', 0, 'eqDiamUm', 0, ...
    'majorUm', 0, 'ecc', 0, 'solidity', 0, 'alignment', 0, 'contrast', 0, ...
    'redness', 0, 'prob', 0, 'quadrant', 0, 'distFoveaDD', 0);
end

function t = classify(e, h)
if e.areaDA >= h.preretinalDA && e.contrast > 0.25
    t = 'preretinal';
elseif e.ecc >= h.flameEcc && e.alignment >= h.flameAlign && e.majorUm >= h.flameMinLenUm
    t = 'flame';
elseif e.eqDiamUm <= 250 && e.ecc < 0.85
    t = 'dot';
else
    t = 'blot';
end
end

function ring = ringPixels(L, k, xx, yy, D)
% pixels of a 3-px band around component k (background for colour contrast)
pad = 6;
r1 = max(1, min(yy) - pad); r2 = min(D, max(yy) + pad);
c1 = max(1, min(xx) - pad); c2 = min(D, max(xx) + pad);
sub = L(r1:r2, c1:c2) == k;
band = imdilate(sub, strel('disk', 4, 0)) & ~imdilate(sub, strel('disk', 1, 0)) & L(r1:r2, c1:c2) == 0;
[by, bx] = find(band);
ring = sub2ind([D D], by + r1 - 1, bx + c1 - 1);
if isempty(ring)
    ring = sub2ind([D D], yy, xx);
end
end
