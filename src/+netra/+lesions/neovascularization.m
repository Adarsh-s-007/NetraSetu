function NV = neovascularization(E, A, cfg)
%NEOVASCULARIZATION Score new-vessel formation on the disc (NVD) and elsewhere (NVE).
%
%   NV = netra.lesions.neovascularization(E, A, cfg)
%
%   New vessels are fine, tortuous, randomly oriented and loop back on
%   themselves, whereas normal vessels branch sparsely and run coherently
%   away from the disc. A fine-vessel map is built at canvas resolution
%   (Frangi at sigma 1-1.6 px, top 15 %, united with the vessel mask) and,
%   over a 0.5-DD sliding window, the detector measures
%     branch     branch points per unit skeleton length
%     entropy    normalised entropy of vessel orientations (6 bins)
%     tortuous   mean (arc / chord - 1) of the skeleton segments
%     loops      small enclosed holes in the vessel mask per window
%     length     skeleton length density (gate: new vessels add length)
%     fine       share of skeleton belonging to vessels <= 0.03 DD wide
%   Each feature becomes a one-sided robust z-score, capped at cfg.nv.zCap so
%   that several features must rise together, against the rest of the
%   same image, separately inside the disc zone and outside it (the disc
%   is naturally vessel-dense). When cfg.nv.normativeModel names a model
%   built from grade-0 images (netra.lesions.trainNVNormative), population
%   statistics replace the intra-image ones.
%
%   NV fields: nvdScore, nveScore, nvdProb, nveProb, candidates (struct:
%   type, x, y, bbox [x y w h] in canvas px, score, prob), scoreMap,
%   fineMask and features (canvas resolution).

nvc = cfg.nv;
V = A.vessels;
F = A.frame;
D = size(E.gN, 1);
DD = F.pxPerDD;
m = E.mask & imerode(E.mask, strel('disk', max(2, round(0.1 * DD)), 0));

% Fine-vessel map at canvas resolution: new vessels are 20-50 um wide and
% largely invisible at the vessel-segmentation resolution.
c = 1 - E.gN;
c(~E.mask) = 0;
fineV = zeros(D);
theta = zeros(D);
for sg = [1.0 1.6]
    H = netra.anatomy.hessian(c, sg);
    Rb = H.l1 ./ (H.l2 - eps);
    S2 = H.l1 .^ 2 + H.l2 .^ 2;
    cc = 0.5 * sqrt(max(S2(m)));
    v = exp(-Rb .^ 2 / 0.5) .* (1 - exp(-S2 / (2 * cc ^ 2 + eps)));
    v(H.l2 >= 0) = 0;
    upd = v > fineV;
    fineV(upd) = v(upd);
    theta(upd) = H.theta(upd);
end
B = (fineV > netra.util.pct(fineV(m), 85) & m) | (V.maskWork & m);
B = bwareaopen(B, 10);
skel = bwmorph(B, 'thin', Inf);

w = max(5, 2 * round(nvc.windowDD * DD / 2) + 1);
fm = max(netra.util.boxMean(double(m), w), 1e-3);
skd = netra.util.boxMean(double(skel), w);
skdN = skd ./ fm;

nb = conv2(double(skel), [1 1 1; 1 0 1; 1 1 1], 'same') .* skel;
branch = skel & nb >= 3;
brn = netra.util.boxMean(double(branch), w) ./ max(skd, 1 / w ^ 2);

% orientation entropy of skeleton pixels
th = mod(theta, pi);
bins = min(floor(th / (pi / 6)) + 1, 6);
ent = zeros(D);
for k = 1:6
    pk = netra.util.boxMean(double(skel & bins == k), w) ./ max(skd, eps);
    ent = ent - pk .* log(pk + eps);
end
ent = ent / log(6);

% tortuosity of skeleton segments, painted on their pixels
segs = netra.util.skeletonSegments(skel, 6);
tmap = zeros(D);
for k = 1:numel(segs)
    tmap(segs(k).idx) = min(segs(k).tortuosity - 1, 2);
end
tor = netra.util.boxMean(tmap, w) ./ max(skd, eps);

% loops: small holes enclosed by vessels
holes = imfill(B, 'holes') & ~B;
holes = holes & ~bwareaopen(holes, max(4, round((0.3 * DD) ^ 2)));
hl = bwlabel(holes, 8);
hc = zeros(D);
if max(hl(:)) > 0
    st = regionprops(hl, 'Centroid');
    for k = 1:numel(st)
        cxy = round(st(k).Centroid);
        hc(cxy(2), cxy(1)) = 1;
    end
end
loops = netra.util.boxMean(hc, w) * w ^ 2;

% share of fine vessels (<= 0.03 DD) in the skeleton
wid = 2 * double(bwdist(~B)) - 1;
fine = netra.util.boxMean(double(skel & wid <= 0.03 * DD), w) ./ max(skd, eps);

feat = struct('branch', brn, 'entropy', ent, 'tortuous', tor, 'loops', loops, ...
    'length', skdN, 'fine', fine);

% ------------------------------------------------ zone-wise robust z-scores
zoneDisc = F.distDisc <= nvc.discZoneDD;
inside = m & fm > 0.7 & skd > 0;
sampleGrid = false(D);
step = max(1, round(nvc.strideDD * DD / 2));
sampleGrid(1:step:end, 1:step:end) = true;
names = {'branch', 'entropy', 'tortuous', 'loops', 'length'};
weights = [1 1 1 1 0.5];
nmodel = loadNormative(nvc.normativeModel);
S = zeros(D);
for z = 1:2
    if z == 1
        zm = zoneDisc;
    else
        zm = ~zoneDisc;
    end
    ref = inside & zm & sampleGrid;
    Sz = zeros(D);
    for k = 1:numel(names)
        f = feat.(names{k});
        if ~isempty(nmodel)
            med = nmodel.median(z, k);
            sd = nmodel.scale(z, k);
        else
            [med, sd] = netra.util.robustStats(f(ref));
        end
        sd = max(sd, 1e-3 + 0.05 * abs(med));
        % one-sided and capped: no single feature can carry the decision
        Sz = Sz + weights(k) * min(nvc.zCap, max(0, (f - med) / sd));
    end
    S(zm) = Sz(zm);
end
% gates: new vessels add fine vessel length
[medL, sdL] = netra.util.robustStats(skdN(inside & sampleGrid));
S = S .* netra.util.sigmoid(skdN, medL, max(sdL, 1e-3)) .* netra.util.sigmoid(fine, 0.55, 0.06);
S(~inside) = 0;

% ---------------------------------------------------------- candidates
C = S > nvc.threshold;
C = bwareaopen(C, max(4, round(nvc.minWindows * (nvc.strideDD * DD) ^ 2 / 4)));
L = bwlabel(C, 8);
cand = struct('type', {}, 'x', {}, 'y', {}, 'bbox', {}, 'score', {}, 'prob', {});
if max(L(:)) > 0
    st = regionprops(L, 'Centroid', 'BoundingBox', 'PixelIdxList');
    for k = 1:numel(st)
        c = st(k).Centroid;
        bb = st(k).BoundingBox;
        sc = max(S(st(k).PixelIdxList));
        dd = hypot(c(1) - F.od(1), c(2) - F.od(2)) / F.pxPerDD;
        if dd <= nvc.discZoneDD
            typ = 'NVD';
        else
            typ = 'NVE';
        end
        cand(end + 1) = struct('type', typ, 'x', c(1), 'y', c(2), 'bbox', bb, ... %#ok<AGROW>
            'score', sc, 'prob', netra.util.sigmoid(sc, nvc.threshold + 1, 1.0));
    end
end
NV = struct();
NV.nvdScore = max([0; S(zoneDisc & inside)]);
NV.nveScore = max([0; S(~zoneDisc & inside)]);
NV.nvdProb = netra.util.sigmoid(NV.nvdScore, nvc.threshold + 1, 1.0);
NV.nveProb = netra.util.sigmoid(NV.nveScore, nvc.threshold + 1, 1.0);
NV.candidates = cand;
NV.scoreMap = S;
NV.fineMask = B;
NV.features = feat;
NV.window = w;
end

function nm = loadNormative(path)
nm = [];
if isempty(path) || ~exist(path, 'file')
    return
end
S = load(path);
nm = S.normative;
end
