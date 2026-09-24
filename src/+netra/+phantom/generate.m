function [rgb, gt] = generate(varargin)
%GENERATE Synthetic colour fundus photograph with complete ground truth.
%
%   [rgb, gt] = netra.phantom.generate('Grade', 2, 'Seed', 7)
%
%   The phantom is rendered physically rather than painted: a pigmented
%   background with choroidal texture and macular pigment, a disc and cup,
%   a vascular tree (netra.phantom.vesselTree) and lesions are combined as
%   reflectance mixing (bright deposits) and Beer-Lambert absorbance (blood),
%   then passed through a camera model (vignetting, optical blur, sensor
%   noise, 8-bit quantisation). Every structure is known exactly, including
%   the sub-pixel centre of each microaneurysm, which is what makes the
%   phantom useful for testing localisation accuracy.
%
%   Options
%     Size       canvas size in px (square)                          1024
%     Seed       random seed                                          1
%     Grade      ICDR level 0..4 of the inserted lesions               0
%     DME        'auto' | 0 | 1 | 2  (IDRiD macular-oedema risk)       'auto'
%     Eye        'R' (disc on image right) | 'L'                       'R'
%     FOVFrac    FOV diameter / canvas size                            0.94
%     DDFrac     disc diameter / FOV diameter                          0.14
%     Pigment    0 (lightly pigmented) .. 1 (heavily pigmented)        0.5
%     Lesions    struct overriding lesion counts, fields:
%                ma, dot, blot, flame, hePerQuadrant (1x4), exClusters,
%                cws, vbQuadrants, irma, nv ('none'|'NVD'|'NVE'), preretinal
%     Degrade    struct passed to netra.phantom.degrade                struct()
%
%   gt fields
%     fov, fovCentre, fovRadius, pxPerDD, umPerPx, od, odRadius, fovea, eye
%     vessels, arteries, vesselWidth    vessel masks and calibre map
%     ma        struct array: x, y (sub-pixel), sigma, sigmaObs, amplitude,
%               diameterUm, quadrant
%     he        struct array: type, x, y, areaPx, quadrant
%     maMask, heMask, exMask, cwsMask, nvMask, irmaMask
%     hePerQuadrant, vbQuadrants, nvType, grade, dme, gradable

d = struct('Size', 1024, 'Seed', 1, 'Grade', 0, 'DME', 'auto', 'Eye', 'R', ...
    'FOVFrac', 0.94, 'DDFrac', 0.14, 'Pigment', 0.5, 'Lesions', struct(), ...
    'Degrade', struct(), 'FoveaJitter', 0.12);
o = netra.util.opts(d, varargin{:});
rng(o.Seed);

N = o.Size;
c = [N N] / 2 + 0.5;
R = o.FOVFrac * N / 2;
DD = o.DDFrac * 2 * R;
umPerPx = 1500 / DD;
eyeSign = 1;
if upper(o.Eye(1)) == 'L'
    eyeSign = -1;
end
fovea = c + DD * o.FoveaJitter * randn(1, 2);
od = fovea + DD * [eyeSign * 2.5, -0.30];
geom = struct('od', od, 'fovea', fovea, 'fovCentre', c, 'fovRadius', R, 'pxPerDD', DD);
[e1, e2] = frameVectors(od, fovea);

[X, Y] = meshgrid(1:N, 1:N);
rC = hypot(X - c(1), Y - c(2));
fov = rC <= R;

L = lesionPlan(o);

% ------------------------------------------------------------ background
base = (1 - o.Pigment) * [0.86 0.46 0.26] + o.Pigment * [0.62 0.27 0.11];
tex = 1 + (0.012 + 0.020 * o.Pigment) * normField(N, DD / 6) + 0.022 * normField(N, DD / 1.3);
img = zeros(N, N, 3);
for k = 1:3
    img(:, :, k) = base(k) * tex;
end
rF = hypot(X - fovea(1), Y - fovea(2));
mac = exp(-rF .^ 2 / (2 * (0.38 * DD) ^ 2));
macDark = [0.16 0.34 0.30];
for k = 1:3
    img(:, :, k) = img(:, :, k) .* (1 - macDark(k) * mac);
end
odR = DD / 2 * (1 + 0.04 * randn);
rOe = hypot(X - od(1), (Y - od(2)) / 1.08);
disc = 1 ./ (1 + exp((rOe - odR) / (0.035 * DD)));
cup = 1 ./ (1 + exp((rOe - 0.38 * odR) / (0.05 * DD)));
img = mixTo(img, 0.78 * disc, [0.98 0.80 0.58]);
img = mixTo(img, 0.55 * cup, [1.00 0.93 0.82]);

% ------------------------------------------------------------- vessels
T = netra.phantom.vesselTree(geom, 'MinWidth', max(0.9, 0.9 * N / 1024));
[T, vbQuadrants] = applyBeading(T, L.vbQuadrants, geom);
[Tnv, nvMaskCL, nvType] = neovessels(L.nv, geom, T);
[Tir, irmaCL] = irmaVessels(L.irma, geom);
S = struct('x', [T.x; Tnv.x; Tir.x], 'y', [T.y; Tnv.y; Tir.y], ...
    'w', [T.w; Tnv.w; Tir.w], 'type', [T.type; Tnv.type; Tir.type]);
[Av, vesselMask, arteryMask, widthMap, Dv] = renderVessels(S, N, DD);

% ------------------------------------------------------ lesion placement
maMask = false(N); heMask = false(N); exMask = false(N); cwsMask = false(N);
Ahe = zeros(N); Ama = zeros(N);
ma = struct('x', {}, 'y', {}, 'sigma', {}, 'sigmaObs', {}, 'amplitude', {}, ...
    'diameterUm', {}, 'quadrant', {});
he = struct('type', {}, 'x', {}, 'y', {}, 'areaPx', {}, 'quadrant', {});
psf = 0.55;
clear0 = @(p, margin) vesselClear(p, margin, Dv, widthMap, N);

% microaneurysms: Gaussian absorbers at sub-pixel positions
for i = 1:L.ma
    sigUm = 8 + 30 * rand ^ 1.5;
    sig = sigUm / umPerPx;
    p = samplePoint(geom, e1, e2, [0.2 3.2], 0, @(p) clear0(p, 2 * sig + 1.5));
    if isempty(p), continue; end
    amp = 0.20 + 0.45 * rand;
    [Ama, M] = stampGaussian(Ama, p, sig, amp, N);
    maMask = maMask | M;
    ma(end + 1) = struct('x', p(1), 'y', p(2), 'sigma', sig, ...
        'sigmaObs', sqrt(sig ^ 2 + psf ^ 2), 'amplitude', amp, ...
        'diameterUm', 2.3548 * sigUm, 'quadrant', quadrantOf(p, fovea, e1, e2)); %#ok<AGROW>
end

% haemorrhages (dot, blot, flame), optionally a fixed count per quadrant
heTypes = [repmat({'dot'}, 1, L.dot), repmat({'blot'}, 1, L.blot), repmat({'flame'}, 1, L.flame)];
heQuad = zeros(1, numel(heTypes));
if ~isempty(L.hePerQuadrant)
    heTypes = {};
    heQuad = [];
    for q = 1:4
        for j = 1:L.hePerQuadrant(q)
            r = rand;
            if r < 0.55, t = 'dot'; elseif r < 0.90, t = 'blot'; else, t = 'flame'; end
            heTypes{end + 1} = t; %#ok<AGROW>
            heQuad(end + 1) = q; %#ok<AGROW>
        end
    end
end
for i = 1:numel(heTypes)
    t = heTypes{i};
    switch t
        case 'dot',   rad = (65 + 55 * rand) / umPerPx;
        case 'blot',  rad = (130 + 150 * rand) / umPerPx;
        otherwise,    rad = (160 + 200 * rand) / umPerPx;
    end
    p = samplePoint(geom, e1, e2, [0.5 3.4], heQuad(i), @(p) clear0(p, 0.6 * rad + 1));
    if isempty(p), continue; end
    switch t
        case 'dot'
            [Ahe, M] = stampEllipse(Ahe, p, rad, rad, 0, 0.85 + 0.25 * rand, 0.7, N);
        case 'blot'
            [Ahe, M] = stampBlot(Ahe, p, rad, 0.95 + 0.3 * rand, N);
        case 'flame'
            radial = atan2(p(2) - od(2), p(1) - od(1));   % nerve-fibre direction
            [Ahe, M] = stampEllipse(Ahe, p, rad, rad * (0.22 + 0.08 * rand), radial, ...
                0.75 + 0.2 * rand, 0.9, N);
    end
    heMask = heMask | M;
    he(end + 1) = struct('type', t, 'x', p(1), 'y', p(2), 'areaPx', nnz(M), ...
        'quadrant', quadrantOf(p, fovea, e1, e2)); %#ok<AGROW>
end
for i = 1:L.preretinal
    p = samplePoint(geom, e1, e2, [1.6 3.0], 0, @(p) true);
    if isempty(p), continue; end
    a = (0.55 + 0.3 * rand) * DD;
    [Ahe, M] = stampBoat(Ahe, p, a, 0.65 * a, 1.7, N);
    heMask = heMask | M;
    he(end + 1) = struct('type', 'preretinal', 'x', p(1), 'y', p(2), 'areaPx', nnz(M), ...
        'quadrant', quadrantOf(p, fovea, e1, e2)); %#ok<AGROW>
end

% hard exudates: circinate clusters of sharp-edged yellow deposits
dme = 0;
Mex = zeros(N);
for i = 1:L.exClusters
    if L.dme == 2 && i == 1
        rng_ = [0.25 0.75];
    else
        rng_ = [1.35 3.0];
    end
    ctr = samplePoint(geom, e1, e2, rng_, 0, @(p) true);
    if isempty(ctr), continue; end
    ring = (0.18 + 0.25 * rand) * DD;
    nb = 12 + randi(24);
    for j = 1:nb
        th = 2 * pi * rand;
        pj = ctr + (ring + 0.07 * DD * randn) * [cos(th) sin(th)];
        if norm(pj - od) < 0.9 * DD || norm(pj - c) > 0.9 * R, continue; end
        rj = (18 + 52 * rand ^ 1.3) / umPerPx;
        [Mex, M] = stampEllipse(Mex, pj, rj, rj * (0.7 + 0.3 * rand), pi * rand, ...
            0.55 + 0.4 * rand, 0.35, N);
        exMask = exMask | M;
    end
end
if any(exMask(:))
    % IDRiD definition: grade 2 if any exudate lies within 1 DD of the fovea
    distEx = min(hypot(X(exMask) - fovea(1), Y(exMask) - fovea(2))) / DD;
    dme = 1 + double(distEx <= 1.0);
end
img = mixTo(img, Mex, [0.97 0.88 0.50]);

% cotton-wool spots: soft, fluffy, whitish, along the arcades
Mcws = zeros(N);
for i = 1:L.cws
    p = samplePoint(geom, e1, e2, [0.9 3.0], 0, @(p) norm(p - od) > 1.2 * DD);
    if isempty(p), continue; end
    r = (0.09 + 0.12 * rand) * DD;
    [Mc, M] = stampBlot(zeros(N), p, r, 1, N, 0.18 * r);
    Mc = Mc .* (0.75 + 0.25 * max(-1, min(1, normField(N, r / 3))));
    Mcws = max(Mcws, (0.45 + 0.2 * rand) * Mc);
    cwsMask = cwsMask | M;
end
img = mixTo(img, Mcws, [0.95 0.85 0.79]);

% -------------------------------------------------------- composition
kV = [0.30 1.00 0.78];
kH = [0.40 1.00 0.86];
kM = [0.33 1.00 0.80];
for k = 1:3
    img(:, :, k) = img(:, :, k) .* exp(-(kV(k) * Av + kH(k) * Ahe + kM(k) * Ama));
end

% camera: illumination fall-off, tilt, optics, aperture, sensor
vig = 0.28 + 0.10 * rand;
phi = 2 * pi * rand;
illum = (1 - vig * (rC / R) .^ 2.4) .* ...
    (1 + 0.05 * rand * ((X - c(1)) * cos(phi) + (Y - c(2)) * sin(phi)) / R);
for k = 1:3
    img(:, :, k) = imgaussfilt(img(:, :, k) .* illum, psf);
end
ap = 1 ./ (1 + exp((rC - R) / 0.7));
for k = 1:3
    img(:, :, k) = img(:, :, k) .* ap + 0.012 * (1 - ap);
end
img = img + (0.004 + 0.006 * sqrt(max(img, 0))) .* randn(size(img));
rgb = round(min(max(img, 0), 1) * 255) / 255;

% ------------------------------------------------------------------ gt
gt = struct();
gt.fov = fov;
gt.fovCentre = c;
gt.fovRadius = R;
gt.pxPerDD = DD;
gt.umPerPx = umPerPx;
gt.od = od;
gt.odRadius = odR;
gt.fovea = fovea;
gt.eye = upper(o.Eye(1));
gt.vessels = vesselMask & fov;
gt.arteries = arteryMask & fov;
gt.vesselWidth = widthMap .* vesselMask;
gt.ma = ma;
gt.he = he;
gt.maMask = maMask;
gt.heMask = heMask;
gt.exMask = exMask;
gt.cwsMask = cwsMask;
gt.nvMask = imdilate(nvMaskCL, strel('disk', max(2, round(0.02 * DD)), 0));
gt.irmaMask = imdilate(irmaCL, strel('disk', 2, 0));
gt.hePerQuadrant = zeros(1, 4);
for i = 1:numel(he)
    if ~strcmp(he(i).type, 'preretinal')
        gt.hePerQuadrant(he(i).quadrant) = gt.hePerQuadrant(he(i).quadrant) + 1;
    end
end
gt.vbQuadrants = vbQuadrants;
gt.nvType = nvType;
gt.grade = o.Grade;
gt.dme = dme;
gt.gradable = true;
gt.issues = {};
gt.lesionPlan = L;

if ~isempty(fieldnames(o.Degrade))
    [rgb, gt] = netra.phantom.degrade(rgb, gt, o.Degrade);
end
end

% ======================================================================
function L = lesionPlan(o)
g = o.Grade;
L = struct('ma', 0, 'dot', 0, 'blot', 0, 'flame', 0, 'hePerQuadrant', [], ...
    'exClusters', 0, 'cws', 0, 'vbQuadrants', 0, 'irma', 0, 'nv', 'none', ...
    'preretinal', 0, 'dme', 0);
switch g
    case 1
        L.ma = randi([3 8]);
    case 2
        L.ma = randi([8 22]);
        L.dot = randi([2 6]);
        L.blot = randi([1 4]);
        L.flame = randi([0 2]);
        L.exClusters = double(rand < 0.6);
        L.cws = randi([0 2]);
    case 3
        L.ma = randi([20 40]);
        L.hePerQuadrant = randi([11 15], 1, 4);
        L.exClusters = double(rand < 0.7);
        L.cws = randi([1 4]);
        L.vbQuadrants = 2 * double(rand < 0.5);
        L.irma = double(rand < 0.4);
    case 4
        L.ma = randi([15 35]);
        L.dot = randi([4 9]);
        L.blot = randi([2 6]);
        L.flame = randi([0 3]);
        L.exClusters = double(rand < 0.5);
        L.cws = randi([0 3]);
        if rand < 0.5, L.nv = 'NVD'; else, L.nv = 'NVE'; end
        L.preretinal = double(rand < 0.35);
end
% macular oedema risk
if ischar(o.DME)
    if L.exClusters > 0
        L.dme = 1 + double(rand < 0.5);
    end
else
    L.dme = o.DME;
    if L.dme > 0
        L.exClusters = max(L.exClusters, 1);
    else
        L.exClusters = 0;
    end
end
f = fieldnames(o.Lesions);
for k = 1:numel(f)
    L.(f{k}) = o.Lesions.(f{k});
end
end

function [e1, e2] = frameVectors(od, fovea)
e1 = (fovea - od) / norm(fovea - od);   % temporal
e2 = [e1(2), -e1(1)];                   % superior (up in the image)
if e2(2) > 0
    e2 = -e2;
end
end

function q = quadrantOf(p, fovea, e1, e2)
dd = p - fovea;
uu = dd * (-e1');
vv = dd * e2';
if uu < 0 && vv >= 0
    q = 1;
elseif uu >= 0 && vv >= 0
    q = 2;
elseif uu >= 0
    q = 3;
else
    q = 4;
end
end

function p = samplePoint(geom, e1, e2, rangeDD, quadrant, accept)
% Rejection-sample a retinal position rangeDD(1)..rangeDD(2) disc diameters
% from the fovea, optionally inside one quadrant, away from the disc.
DD = geom.pxPerDD;
p = [];
angRange = [0 2 * pi];
if quadrant > 0
    lims = [pi / 2 pi; 0 pi / 2; 3 * pi / 2 2 * pi; pi 3 * pi / 2];
    angRange = lims(quadrant, :);
end
nasal = -e1;
for attempt = 1:400
    r = rangeDD(1) + (rangeDD(2) - rangeDD(1)) * sqrt(rand);
    th = angRange(1) + (angRange(2) - angRange(1)) * rand;
    cand = geom.fovea + DD * r * (cos(th) * nasal + sin(th) * e2);
    if norm(cand - geom.fovCentre) > 0.9 * geom.fovRadius
        continue
    end
    if norm(cand - geom.od) < 1.0 * DD
        continue
    end
    if accept(cand)
        p = cand;
        return
    end
end
end

function ok = vesselClear(p, margin, Dv, widthMap, N)
r = min(max(round(p(2)), 1), N);
cc = min(max(round(p(1)), 1), N);
ok = Dv(r, cc) > widthMap(r, cc) / 2 + margin;
end

function F = normField(N, sigma)
% Smooth zero-mean, unit-variance random field with correlation length sigma.
n = max(8, ceil(N / max(sigma / 3, 1)));
F = imgaussfilt(randn(n + 6), 1.5);
F = F(4:end - 3, 4:end - 3);
F = imresize(F, [N N], 'bilinear');
F = (F - mean(F(:))) / max(std(F(:)), eps);
end

function img = mixTo(img, m, colour)
for k = 1:3
    img(:, :, k) = img(:, :, k) .* (1 - m) + colour(k) * m;
end
end

function [T, quads] = applyBeading(T, nQuad, geom)
quads = [];
if nQuad <= 0
    return
end
veins = find([T.vessels.type] == 2 & [T.vessels.isMajor]);
avail = unique([T.vessels(veins).quadrant]);
avail = avail(randperm(numel(avail)));
quads = sort(avail(1:min(nQuad, numel(avail))));
for v = veins
    if ~any(T.vessels(v).quadrant == quads)
        continue
    end
    idx = T.vessels(v).first:T.vessels(v).last;
    x = T.x(idx);
    y = T.y(idx);
    s = [0; cumsum(hypot(diff(x), diff(y)))];
    w0 = T.w(idx);
    dOD = hypot(x - geom.od(1), y - geom.od(2)) / geom.pxPerDD;
    lambda = 3.2 * median(w0);
    bead = 1 + 0.40 * max(0, sin(2 * pi * s / lambda)) .^ 2;
    bead(dOD < 0.7) = 1;
    T.w(idx) = w0 .* bead;
end
end

function [Tn, clMask, nvType] = neovessels(kind, geom, T)
DD = geom.pxPerDD;
Tn = struct('x', zeros(0, 1), 'y', zeros(0, 1), 'w', zeros(0, 1), 'type', zeros(0, 1));
N = 2 * geom.fovCentre(1) - 1;
clMask = false(round(N));
nvType = 'none';
if strcmp(kind, 'none') || isempty(kind)
    return
end
nvType = kind;
if strcmp(kind, 'NVD')
    ctr = geom.od + 0.35 * DD * randn(1, 2) / 2;
    rad = 0.45 * DD;
else
    veins = find([T.vessels.type] == 2 & [T.vessels.isMajor]);
    ctr = [];
    for attempt = 1:50
        v = veins(randi(numel(veins)));
        idx = T.vessels(v).first:T.vessels(v).last;
        j = idx(randi(numel(idx)));
        p = [T.x(j) T.y(j)];
        dd = norm(p - geom.od) / DD;
        if dd > 1.8 && dd < 4.2 && norm(p - geom.fovCentre) < 0.8 * geom.fovRadius
            ctr = p;
            break
        end
    end
    if isempty(ctr)
        ctr = geom.fovea + [0 -1.8 * DD];
    end
    rad = 0.40 * DD;
end
nSeg = 16 + randi(14);
xs = {}; ys = {}; ws = {};
for s = 1:nSeg
    p = ctr + rad * sqrt(rand) * [cos(2 * pi * rand) sin(2 * pi * rand)];
    h = 2 * pi * rand;
    kap = 0;
    len = (0.15 + 0.3 * rand) * DD;
    n = ceil(len / 0.5);
    P = zeros(n, 2);
    m = 0;
    for it = 1:n
        kap = 0.88 * kap + 0.035 * randn;
        h = h + kap;
        p = p + 0.5 * [cos(h) sin(h)];
        if norm(p - ctr) > 1.15 * rad
            h = atan2(ctr(2) - p(2), ctr(1) - p(1)) + 0.6 * randn;   % curl back: loops
        end
        m = m + 1;
        P(m, :) = p;
    end
    P = P(1:m, :);
    xs{end + 1} = P(:, 1); %#ok<AGROW>
    ys{end + 1} = P(:, 2); %#ok<AGROW>
    ws{end + 1} = (0.012 + 0.008 * rand) * DD * ones(m, 1); %#ok<AGROW>
end
Tn.x = vertcat(xs{:});
Tn.y = vertcat(ys{:});
Tn.w = vertcat(ws{:});
Tn.type = 3 * ones(numel(Tn.x), 1);
ok = Tn.x >= 1 & Tn.y >= 1 & Tn.x <= N & Tn.y <= N;
clMask(sub2ind(size(clMask), round(Tn.y(ok)), round(Tn.x(ok)))) = true;
end

function [Ti, clMask] = irmaVessels(n, geom)
DD = geom.pxPerDD;
N = round(2 * geom.fovCentre(1) - 1);
Ti = struct('x', zeros(0, 1), 'y', zeros(0, 1), 'w', zeros(0, 1), 'type', zeros(0, 1));
clMask = false(N);
for k = 1:n
    th = 2 * pi * rand;
    ctr = geom.fovea + (1.6 + 0.8 * rand) * DD * [cos(th) sin(th)];
    if norm(ctr - geom.od) < 1.3 * DD
        ctr = 2 * geom.fovea - ctr;            % mirror away from the disc
    end
    for s = 1:(3 + randi(3))
        p = ctr + 0.2 * DD * randn(1, 2);
        h = 2 * pi * rand;
        kap = 0;
        m = ceil((0.15 + 0.15 * rand) * DD / 0.5);
        P = zeros(m, 2);
        for it = 1:m
            kap = 0.9 * kap + 0.015 * randn;
            h = h + kap;
            p = p + 0.5 * [cos(h) sin(h)];
            P(it, :) = p;
        end
        Ti.x = [Ti.x; P(:, 1)];
        Ti.y = [Ti.y; P(:, 2)];
        Ti.w = [Ti.w; (0.018 + 0.008 * rand) * DD * ones(m, 1)];
        Ti.type = [Ti.type; 4 * ones(m, 1)];
    end
end
ok = Ti.x >= 1 & Ti.y >= 1 & Ti.x <= N & Ti.y <= N;
clMask(sub2ind([N N], round(Ti.y(ok)), round(Ti.x(ok)))) = true;
end

function [Av, vmask, amask, widthMap, D] = renderVessels(S, N, DD)
ix = round(S.x);
iy = round(S.y);
ok = ix >= 1 & iy >= 1 & ix <= N & iy <= N;
ix = ix(ok); iy = iy(ok);
w = S.w(ok); ty = S.type(ok);
lin = sub2ind([N N], iy, ix);
[~, order] = sort(w);                     % widest sample wins a shared pixel
Wc = zeros(N); Tc = zeros(N);
Wc(lin(order)) = w(order);
Tc(lin(order)) = ty(order);
[D, IDX] = bwdist(Wc > 0);
D = double(D);
IDX = double(IDX);
widthMap = Wc(IDX);
typ = Tc(IDX);
prof = 1 ./ (1 + exp((D - widthMap / 2) / 0.45));
amp = 0.42 * (typ == 1) + 0.72 * (typ == 2) + 0.55 * (typ == 3) + 0.62 * (typ == 4);
amp = amp .* (0.25 + 0.75 * min(1, widthMap / (0.075 * DD)));
reflex = (typ == 1) .* (widthMap >= 4) .* 0.35 .* exp(-D .^ 2 ./ (2 * (0.13 * widthMap) .^ 2));
Av = amp .* prof .* (1 - reflex);
vmask = D <= widthMap / 2 & (typ == 1 | typ == 2);
amask = vmask & typ == 1;
end

function [A, M] = stampGaussian(A, p, sig, amp, N)
w = windowBox(p, 4 * sig + 2, N);
[xx, yy] = meshgrid(w(3):w(4), w(1):w(2));
r2 = (xx - p(1)) .^ 2 + (yy - p(2)) .^ 2;
A(w(1):w(2), w(3):w(4)) = A(w(1):w(2), w(3):w(4)) + amp * exp(-r2 / (2 * sig ^ 2));
M = false(N);
M(w(1):w(2), w(3):w(4)) = r2 <= max(1, 1.1774 * sig) ^ 2;
end

function [A, M] = stampEllipse(A, p, a, b, theta, amp, soft, N)
w = windowBox(p, max(a, b) + 4 * soft + 2, N);
[xx, yy] = meshgrid(w(3):w(4), w(1):w(2));
u = (xx - p(1)) * cos(theta) + (yy - p(2)) * sin(theta);
v = -(xx - p(1)) * sin(theta) + (yy - p(2)) * cos(theta);
rho = sqrt((u / a) .^ 2 + (v / b) .^ 2);
prof = 1 ./ (1 + exp((rho - 1) * min(a, b) / max(soft, 0.2)));
if a > 2.5 * b                               % feathered flame ends
    prof = prof .* max(0, 1 - (abs(u) / a) .^ 4);
end
A(w(1):w(2), w(3):w(4)) = max(A(w(1):w(2), w(3):w(4)), amp * prof);
M = false(N);
M(w(1):w(2), w(3):w(4)) = prof > 0.5;
end

function [A, M] = stampBlot(A, p, r, amp, N, soft)
if nargin < 6
    soft = 0.8;
end
M = false(N);
for j = 1:(2 + randi(3))
    off = 0.45 * r * randn(1, 2);
    a = r * (0.6 + 0.4 * rand);
    b = a * (0.55 + 0.45 * rand);
    [A, Mj] = stampEllipse(A, p + off, a, b, pi * rand, amp, soft, N);
    M = M | Mj;
end
end

function [A, M] = stampBoat(A, p, a, b, amp, N)
w = windowBox(p, a + 4, N);
[xx, yy] = meshgrid(w(3):w(4), w(1):w(2));
rho = sqrt(((xx - p(1)) / a) .^ 2 + ((yy - p(2)) / b) .^ 2);
prof = 1 ./ (1 + exp((rho - 1) * b / 1.2));
prof = prof .* (1 ./ (1 + exp(-((yy - (p(2) - 0.25 * b)) / 1.0))));   % flat fluid level
A(w(1):w(2), w(3):w(4)) = max(A(w(1):w(2), w(3):w(4)), amp * prof);
M = false(N);
M(w(1):w(2), w(3):w(4)) = prof > 0.5;
end

function w = windowBox(p, half, N)
w = [max(1, floor(p(2) - half)), min(N, ceil(p(2) + half)), ...
     max(1, floor(p(1) - half)), min(N, ceil(p(1) + half))];
end
