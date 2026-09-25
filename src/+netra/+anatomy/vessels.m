function V = vessels(gN, mask, cfg, varargin)
%VESSELS Retinal vessel segmentation by fusing three complementary detectors.
%
%   V = netra.anatomy.vessels(gN, mask, cfg) segments vessels in the
%   illumination-normalised green channel gN (background = 1) of a
%   standardised canvas. Work is done at cfg.scale.vesselDiameter, i.e. at
%   DRIVE-like resolution where the published detector parameters apply.
%
%   Detectors, each run on the inverted contrast c = 1 - gN:
%     hessian  multiscale Frangi vesselness (Frangi et al., MICCAI 1998);
%              also yields the local vessel orientation
%     line     multiscale line detector (Nguyen et al., Pattern Recognit 2013):
%              line average minus window average, L = 1:2:15, W = 15,
%              12 orientations, standardised and combined
%     tophat   supremum of openings by linear structuring elements (Zana &
%              Klein, IEEE TIP 2001): keeps only elongated structures, so it
%              suppresses microaneurysms and haemorrhages
%   Responses are robustly normalised and averaged (weights in
%   cfg.vessels.weights, or a logistic model learned on DRIVE when
%   cfg.vessels.model is set), then thresholded by hysteresis.
%
%   Name-value options: 'Detectors' - cell array subset of {'hessian',
%   'line', 'tophat'} (used by the single-technique ablation).
%
%   V fields (vessel resolution unless noted)
%     prob, mask            fused response in [0,1] and binary mask
%     probWork, maskWork    the same, resampled to the input canvas
%     response              struct of the individual normalised detectors
%     contrast              inverted contrast 1 - gN (the fusion model's 4th input)
%     theta                 vessel direction (radians), skeleton, width (px)
%     thick                 mask of major vessels (calibre >= thickWidthDD)
%     scale                 vessel-resolution px per canvas px
%     fraction              vessel pixel fraction of the FOV

o = netra.util.opts(struct('Detectors', {{'hessian', 'line', 'tophat'}}), varargin{:});
vc = cfg.vessels;
D = size(gN, 1);
scale = cfg.scale.vesselDiameter / (D / 1.02);         % canvas has a 2 % margin
Dv = round(D * scale);
g = netra.util.imscale(gN, [Dv Dv]);
m = imresize(mask, [Dv Dv], 'nearest');
mIn = imerode(m, strel('disk', 2, 0));
c = 1 - g;
c(~m) = 0;
c = max(c, -0.2);

resp = struct();
use = @(name) any(strcmp(o.Detectors, name));

% ------------------------------------------------------------- Hessian
% always computed: it also provides the vessel orientation map
theta = zeros(Dv);
best = zeros(Dv);
for s = vc.hessianSigmas
    H = netra.anatomy.hessian(c, s);
    Rb = H.l1 ./ (H.l2 - eps);
    S2 = H.l1 .^ 2 + H.l2 .^ 2;
    cc = vc.frangiC * sqrt(max(S2(mIn)));
    v = exp(-Rb .^ 2 / (2 * vc.frangiBeta ^ 2)) .* (1 - exp(-S2 / (2 * cc ^ 2 + eps)));
    v(H.l2 >= 0) = 0;
    upd = v > best;
    best(upd) = v(upd);
    theta(upd) = H.theta(upd);
end
resp.hessian = normalise(best, mIn);

% ----------------------------------------------------- line detector
if use('line')
    resp.line = normalise(lineDetector(c, m, vc), mIn);
end

% ------------------------------------------------ morphological tophat
if use('tophat')
    acc = zeros(Dv);
    for len = vc.tophatLengths
        sup = zeros(Dv);
        for a = 0:15:165
            sup = max(sup, imopen(c, netra.util.lineSE(len, a)));
        end
        acc = acc + sup;
    end
    resp.tophat = normalise(acc / numel(vc.tophatLengths), mIn);
end

% --------------------------------------------------------------- fuse
names = fieldnames(resp);
names = names(cellfun(@(n) use(n), names));
if isfield(vc, 'model') && isstruct(vc.model) && numel(names) == 3
    X = [resp.hessian(:), resp.line(:), resp.tophat(:), c(:)];
    P = netra.util.sigmoid([ones(numel(c), 1), X] * vc.model.beta(:));
    P = reshape(P, Dv, Dv);
else
    P = zeros(Dv);
    wsum = 0;
    for k = 1:numel(names)
        wk = vc.weights.(names{k});
        P = P + wk * resp.(names{k});
        wsum = wsum + wk;
    end
    P = P / wsum;
end
P(~m) = 0;
P = min(max(P, 0), 1);

% --------------------------------------------------- hysteresis threshold
vals = P(mIn);
tHigh = netra.util.pct(vals, 100 * (1 - vc.highFraction));
tLow = netra.util.pct(vals, 100 * (1 - vc.lowFraction));
strong = P >= tHigh & m;
weak = P >= tLow & m;
B = imreconstruct(strong, weak);
DDv = cfg.scale.ddPerFOV * 2 * (Dv / 2 / 1.02);
B = bwareaopen(B, max(4, round(vc.minAreaDD2 * DDv ^ 2)));
% compact, wide components are not vessels: the fovea, blot haemorrhages,
% pigment clumps. They are removed here and handed to the lesion stage.
L = bwlabel(B, 8);
blobs = false(Dv);
if max(L(:)) > 0
    st = regionprops(L, 'Solidity', 'Eccentricity', 'MinorAxisLength');
    isBlob = [st.Solidity] > 0.70 & [st.Eccentricity] < 0.95 & ...
        [st.MinorAxisLength] > 0.12 * DDv;
    if any(isBlob)
        blobs = ismember(L, find(isBlob));
        B = B & ~blobs;
    end
end

% ------------------------------------------------------- morphometrics
skel = bwmorph(B, 'thin', Inf);
dist = double(bwdist(~B));
width = 2 * dist - 1;
width(~skel) = 0;
thick = B & imopen(B, strel('disk', max(1, round(0.5 * vc.thickWidthDD * DDv)), 0));
% a major vessel is long as well as wide: drop short compact pieces
% (microaneurysms and small haemorrhages that the detectors also light up)
Lt = bwlabel(thick, 8);
if max(Lt(:)) > 0
    st = regionprops(Lt, 'MajorAxisLength');
    short = find([st.MajorAxisLength] < 0.35 * DDv);
    thick(ismember(Lt, short)) = false;
end

V = struct();
V.prob = P;
V.mask = B;
V.response = resp;
V.contrast = c;                          % inverted green contrast (fusion input)
V.theta = theta;
V.skeleton = skel;
V.width = width;
V.thick = thick;
V.blobs = blobs;
V.scale = Dv / D;
V.fovMask = m;
V.thresholds = [tLow tHigh];
V.fraction = nnz(B) / max(nnz(m), 1);
V.probWork = imresize(P, [D D], 'bilinear');
V.maskWork = imresize(double(B), [D D], 'bilinear') >= 0.5;
V.thickWork = imresize(double(thick), [D D], 'bilinear') >= 0.5;
end

% ======================================================================
function n = normalise(x, m)
% Map the FOV median to 0 and the 99th percentile to 1 (robust to lesion load).
p = netra.util.pct(x(m), [50 99]);
n = (x - p(1)) / max(p(2) - p(1), eps);
n = min(max(n, 0), 1.25) / 1.25;
end

function R = lineDetector(c, m, vc)
% Nguyen et al. (2013): R = (sum_L Rbar_L + Ibar) / (nL + 1), where
% R_L = max_theta mean(line_L,theta) - mean(W x W window), standardised.
W = vc.lineWindow;
Ls = vc.lineScales;
nAng = vc.lineAngles;
avgW = imfilter(c, ones(W) / W ^ 2, 'replicate');
half = (max(Ls) - 1) / 2;
best = -Inf(size(c, 1), size(c, 2), numel(Ls));
for a = 0:nAng - 1
    ang = a * pi / nAng;
    acc = c;
    for t = 1:half
        dx = round(t * cos(ang));
        dy = round(-t * sin(ang));
        acc = acc + netra.util.shift(c, dy, dx) + netra.util.shift(c, -dy, -dx);
        L = 2 * t + 1;
        j = find(Ls == L, 1);
        if ~isempty(j)
            best(:, :, j) = max(best(:, :, j), acc / L);
        end
    end
    j = find(Ls == 1, 1);
    if ~isempty(j)
        best(:, :, j) = max(best(:, :, j), c);
    end
end
R = zeros(size(c));
for j = 1:numel(Ls)
    r = best(:, :, j) - avgW;
    R = R + standardise(r, m);
end
R = (R + standardise(c, m)) / (numel(Ls) + 1);
end

function z = standardise(x, m)
v = x(m);
z = (x - mean(v)) / max(std(v), eps);
end
