function EX = exudates(E, A, cfg)
%EXUDATES Hard exudates, cotton-wool spots and the macular-oedema risk grade.
%
%   EX = netra.lesions.exudates(E, A, cfg)
%
%   Bright candidates are pixels of the brightening image b = gN - 1 above
%   an adaptive level, grown by hysteresis from pixels 1.5x above it. The
%   disc (cfg.ex.odExclusion disc radii), the vessel light reflex (vessel
%   mask) and the FOV rim are excluded. Each component is described by
%     sharpness   mean gradient magnitude on its boundary divided by its
%                 contrast (1 / edge width, px^-1) - exudates are sharply
%                 demarcated, cotton-wool spots are fluffy
%     yellowness  excess of Lab b* over the surrounding retina - lipid is
%                 yellow, nerve-fibre swelling is white
%     size, elongation and alignment: the nerve-fibre-layer sheen of young
%                 eyes is elongated, parallel to and hugging a major vessel
%   and classified as 'EX', 'CWS' or discarded.
%
%   Macular oedema risk (IDRiD protocol, clinically significant surrogate):
%     dme = 0  no hard exudates
%           1  exudates, none within cfg.ex.dmeRadiusDD (1 DD) of the fovea
%           2  exudates within 1 DD of the fovea
%   centreInvolved flags exudates within ~500 um (1/3 DD) of the fovea.

x = cfg.ex;
F = A.frame;
D = size(E.gN, 1);
DD = F.pxPerDD;
mask = E.mask & F.distDisc * DD > x.odExclusion * F.odRadius & ...
    imerode(E.mask, strel('disk', max(2, round(0.08 * DD)), 0));
vess = imdilate(A.vessels.maskWork, true(3));

b = E.gN - 1;
b(~E.mask) = 0;
b = imgaussfilt(b, 0.7);
[med, rs] = netra.util.robustStats(b(mask & ~vess));
T = max(x.minBrightening, med + x.thresholdK * rs);
strong = b > 1.5 * T & mask & ~vess;
weak = b > T & mask & ~vess;
C = imreconstruct(strong, weak);
C = bwareaopen(C, 3);

% nearest-vessel distance and direction, for rejecting the bright sheen
% that runs alongside the arcades (nerve-fibre-layer reflex, young eyes)
[dV, idxV] = bwdist(A.vessels.maskWork);
dV = double(dV);
idxV = double(idxV);
thetaW = imresize(A.vessels.theta, [D D], 'nearest');

lab = rgb2lab(E.rgbN);
bstar = lab(:, :, 3);
bstarBg = median(bstar(mask & ~vess & ~C));
[gx, gy] = gradient(imgaussfilt(E.gN, 0.8));
gmag = hypot(gx, gy);

L = bwlabel(C, 8);
st = regionprops(L, 'Area', 'Centroid', 'Eccentricity', 'MinorAxisLength', ...
    'MajorAxisLength', 'Solidity', 'PixelIdxList');
per = bwperim(C);
ex = repmat(emptyEntry(), 0, 1);
cws = repmat(emptyEntry(), 0, 1);
exMask = false(D);
cwsMask = false(D);
sg = @netra.util.sigmoid;
for k = 1:numel(st)
    pix = st(k).PixelIdxList;
    e = emptyEntry();
    e.x = st(k).Centroid(1);
    e.y = st(k).Centroid(2);
    e.areaPx = st(k).Area;
    e.eqDiamDD = 2 * sqrt(st(k).Area / pi) / DD;
    e.contrast = mean(b(pix));
    bp = pix(per(pix));
    if isempty(bp)
        bp = pix;
    end
    e.sharpness = mean(gmag(bp)) / max(e.contrast, eps);
    e.yellowness = mean(bstar(pix)) - bstarBg;
    e.ecc = st(k).Eccentricity;
    thin = st(k).Eccentricity > 0.97 && st(k).MinorAxisLength < 0.03 * DD;
    [yy0, xx0] = ind2sub([D D], pix);
    mx = mean(xx0); my = mean(yy0);
    th = 0.5 * atan2(2 * mean((xx0 - mx) .* (yy0 - my)), mean((xx0 - mx) .^ 2) - mean((yy0 - my) .^ 2));
    ci = sub2ind([D D], min(max(round(my), 1), D), min(max(round(mx), 1), D));
    parallel = abs(cos(th - thetaW(idxV(ci)))) > 0.9;
    reflex = st(k).Eccentricity > 0.85 && parallel && dV(ci) < 0.12 * DD;
    yi = min(max(round(e.y), 1), D);
    xi = min(max(round(e.x), 1), D);
    e.quadrant = F.quadrant(yi, xi);
    [yy, xx] = ind2sub([D D], pix);
    e.distFoveaDD = min(hypot(xx - F.fovea(1), yy - F.fovea(2))) / DD;
    if thin || reflex
        continue                                   % nerve-fibre sheen / vessel reflex
    end
    isCWS = e.eqDiamDD >= x.cwsMinDD && e.eqDiamDD <= x.cwsMaxDD && ...
        e.sharpness < x.sharpEdge && e.yellowness < 2 * x.minYellow && ...
        e.ecc < x.cwsMaxEcc && st(k).Solidity >= x.cwsMinSolidity;
    if isCWS
        e.type = 'CWS';
        e.prob = sg(e.contrast, T, 0.25 * T) * sg(x.sharpEdge - e.sharpness, 0, 0.08);
        cws(end + 1, 1) = e; %#ok<AGROW>
        cwsMask(pix) = true;
    elseif e.yellowness >= x.minYellow || e.sharpness >= x.sharpEdge
        e.type = 'EX';
        e.prob = sg(e.contrast, T, 0.25 * T) * ...
            max(sg(e.yellowness, x.minYellow, 1.0), sg(e.sharpness, x.sharpEdge, 0.08));
        ex(end + 1, 1) = e; %#ok<AGROW>
        exMask(pix) = true;
    end
end

EX = struct();
EX.list = ex;
EX.cws = cws;
EX.mask = exMask;
EX.cwsMask = cwsMask;
EX.threshold = T;
good = ex([ex.prob] >= 0.5);
EX.count = numel(good);
EX.cwsCount = sum([cws.prob] >= 0.5);
if isempty(good)
    EX.minDistFoveaDD = Inf;
    EX.areaDD2 = 0;
    EX.dme = 0;
    EX.centreInvolved = false;
else
    EX.minDistFoveaDD = min([good.distFoveaDD]);
    EX.areaDD2 = sum([good.areaPx]) / DD ^ 2;
    EX.dme = 1 + double(EX.minDistFoveaDD <= x.dmeRadiusDD);
    EX.centreInvolved = EX.minDistFoveaDD <= x.centreRadiusDD;
end
EX.areaInnerDD2 = nnz(exMask & F.zone.inner) / DD ^ 2;
end

function e = emptyEntry()
e = struct('x', 0, 'y', 0, 'type', 'EX', 'areaPx', 0, 'eqDiamDD', 0, 'contrast', 0, ...
    'sharpness', 0, 'yellowness', 0, 'ecc', 0, 'prob', 0, 'quadrant', 0, 'distFoveaDD', 0);
end
