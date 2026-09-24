function MA = microaneurysms(E, A, cfg)
%MICROANEURYSMS Detect and characterise microaneurysms with sub-pixel precision.
%
%   MA = netra.lesions.microaneurysms(E, A, cfg) works on the darkening
%   image d = 1 - gN of the standardised canvas:
%
%   1. Vessel suppression - supremum of openings with 12 linear structuring
%      elements of length 0.2 DD keeps every structure that contains a line
%      at least that long (vessels); d minus that supremum leaves only
%      compact dark objects (Spencer et al. 1996; Walter et al. 2007).
%   2. Candidates - scale-normalised Laplacian-of-Gaussian maxima over
%      sigma = 9..63 um whose robust z-score exceeds cfg.ma.thresholdK.
%   3. Characterisation - each candidate is fitted with a Gaussian on a
%      tilted-plane background (netra.lesions.fitGaussian2D): sub-pixel
%      centre, width, amplitude, goodness of fit, localisation standard
%      error and the Cramer-Rao bound, with neighbouring vessel pixels
%      excluded from the fit.
%   4. Scoring - a transparent product of soft criteria (SNR against local
%      texture, fit quality, size 15-250 um, roundness, isolation - no
%      vessel leaving the dot - and blood colour), or the
%      posterior of a classifier trained on IDRiD when models/ma_classifier.mat
%      exists. Red dots above 125 um are labelled dot haemorrhages.
%
%   MA.list fields: x, y (canvas px, sub-pixel), sigmaPx, diameterUm,
%   amplitude, snr, r2, roundness, redness, onVessel, exitRatio, seXY, crlb, prob,
%   class ('MA' | 'dot'), quadrant, distFoveaDD.
%   MA.mask marks every accepted MA (prob >= 0.5) at its fitted FWHM.

m = cfg.ma;
F = A.frame;
mask = E.mask;
D = size(E.gN, 1);
DD = F.pxPerDD;
umPx = F.umPerPx;

d = 1 - E.gN;
d(~mask) = 0;
d = imgaussfilt(d, 0.5);

% ------------------------------------------------- 1. vessel suppression
len = 2 * floor(m.openingDD * DD / 2) + 1;
sup = zeros(D);
for a = 0:(180 / m.openingAngles):179.99
    sup = max(sup, imopen(d, netra.util.lineSE(len, a)));
end
r = max(d - sup, 0);

% --------------------------------------------------- 2. LoG candidates
sig = m.sigmaUm / umPx;
sig = sig(sig >= 0.6 & sig <= 0.12 * DD);
if isempty(sig)
    sig = 1;
end
B = zeros(D);
S = ones(D);
Rnd = zeros(D);
for k = 1:numel(sig)
    H = netra.anatomy.hessian(r, sig(k));
    resp = -(H.l1 + H.l2);
    upd = resp > B;
    B(upd) = resp(upd);
    S(upd) = sig(k);
    ratio = H.l1 ./ min(H.l2, -eps);                 % 1 = perfectly round
    Rnd(upd) = ratio(upd);
end
valid = mask & F.distDisc > 0.6 & ~A.vessels.thickWork & ...
    imerode(mask, strel('disk', max(2, round(0.08 * DD)), 0));
% B approximates half the blob amplitude at the matched scale. Most of r is
% exactly zero after the opening, so a plain robust z degenerates; the
% spread is floored by the measured image noise instead.
[med, rs] = netra.util.robustStats(B(valid));
rs = max(rs, 0.35 * max(E.noise, 1e-3));
Z = (B - med) / rs;
peaks = imregionalmax(B) & valid & Z > m.thresholdK & ...
    B > max(0.5 * m.minContrast, 0.3 * m.minAmplitude);
idx = find(peaks);
[~, order] = sort(B(idx), 'descend');
idx = idx(order(1:min(numel(order), m.maxCandidates)));

% ------------------------------------------------ 3. sub-pixel fitting
vmask = A.vessels.maskWork;
noiseD = max(E.noise, 1e-3);
rgbN = E.rgbN;
list = repmat(emptyEntry(), 0, 1);
taken = false(D);
for i = 1:numel(idx)
    [py, px] = ind2sub([D D], idx(i));
    if taken(py, px)
        continue
    end
    s0 = S(py, px);
    rad = ceil(m.fitRadius * s0 + 2);
    r1 = py - rad; r2 = py + rad; c1 = px - rad; c2 = px + rad;
    if r1 < 1 || c1 < 1 || r2 > D || c2 > D
        continue
    end
    P = d(r1:r2, c1:c2);
    % refine the integer peak with a 3x3 quadratic before fitting
    [ox, oy] = quadPeak(B(py - 1:py + 1, px - 1:px + 1));
    W = double(~(vmask(r1:r2, c1:c2) & ...
        hypot((c1:c2) - px, ((r1:r2)' - py)) > 1.5 * s0 + 1));
    fit = netra.lesions.fitGaussian2D(P, [rad + 1 + ox, rad + 1 + oy, s0, ...
        max(r(py, px), 0.01)], 'Weights', W, 'SigmaMax', 0.15 * DD);
    x = c1 - 1 + fit.x0;
    y = r1 - 1 + fit.y0;
    if x < 1 || y < 1 || x > D || y > D
        continue
    end
    e = emptyEntry();
    e.x = x; e.y = y;
    yi = min(max(round(y), 1), D);
    xi = min(max(round(x), 1), D);
    e.sigmaPx = fit.s;
    e.diameterUm = 2.3548 * fit.s * umPx;
    e.amplitude = fit.a;
    e.snr = fit.a / max([noiseD, fit.resSigma, localTexture(d, vmask, xi, yi, fit.s)]);
    e.r2 = fit.r2;
    e.roundness = Rnd(py, px);
    e.seXY = fit.seXY;
    e.crlb = fit.crlb;
    e.onVessel = onVessel(vmask, xi, yi, 2.3548 * fit.s);
    e.exitRatio = exitRatio(d, x, y, fit.s, fit.a, fit.b(1));
    e.redness = rednessIndex(rgbN, xi, yi, max(1, round(fit.s)), cfg);
    e.quadrant = F.quadrant(yi, xi);
    e.distFoveaDD = F.distFovea(yi, xi);
    e.prob = score(e, m);
    if e.diameterUm > m.maxMAUm
        e.class = 'dot';
    else
        e.class = 'MA';
    end
    list(end + 1, 1) = e; %#ok<AGROW>
    % suppress weaker maxima inside this blob
    rr = max(1, round(1.5 * fit.s));
    taken(max(1, yi - rr):min(D, yi + rr), max(1, xi - rr):min(D, xi + rr)) = true;
end

% ------------------------------------------ optional learned classifier
list = applyClassifier(list, cfg);

MA = struct();
MA.list = list;
MA.candidates = numel(idx);
MA.response = Z;
MA.mask = false(D);
[Xg, Yg] = meshgrid(1:D, 1:D);
for i = 1:numel(list)
    if list(i).prob >= 0.5
        rad = max(1, 1.1774 * list(i).sigmaPx);
        w = [max(1, floor(list(i).y - rad - 1)), min(D, ceil(list(i).y + rad + 1)), ...
             max(1, floor(list(i).x - rad - 1)), min(D, ceil(list(i).x + rad + 1))];
        sub = (Xg(w(1):w(2), w(3):w(4)) - list(i).x) .^ 2 + ...
              (Yg(w(1):w(2), w(3):w(4)) - list(i).y) .^ 2 <= rad ^ 2;
        MA.mask(w(1):w(2), w(3):w(4)) = MA.mask(w(1):w(2), w(3):w(4)) | sub;
    end
end
end

% ======================================================================
function e = emptyEntry()
e = struct('x', 0, 'y', 0, 'sigmaPx', 0, 'diameterUm', 0, 'amplitude', 0, ...
    'snr', 0, 'r2', 0, 'roundness', 0, 'redness', 0, 'onVessel', false, ...
    'seXY', 0, 'crlb', 0, 'exitRatio', 0, 'prob', 0, 'class', 'MA', 'quadrant', 0, ...
    'distFoveaDD', 0);
end

function t = localTexture(d, vmask, x, y, s)
% robust spread of the darkening image in an annulus 2.5-5 sigma around the
% candidate, vessels excluded: the "noise" a grader compares a dot against
D = size(d, 1);
x = min(x, D); y = min(y, D);
R = max(6, ceil(5 * s));
r1 = max(1, y - R); r2 = min(D, y + R);
c1 = max(1, x - R); c2 = min(D, x + R);
[Xw, Yw] = meshgrid(c1:c2, r1:r2);
dist = hypot(Xw - x, Yw - y);
ring = dist >= max(2.5 * s, 3) & dist <= R & ~vmask(r1:r2, c1:c2);
v = d(r1:r2, c1:c2);
v = v(ring);
if numel(v) < 10
    t = 0;
    return
end
[~, t] = netra.util.robustStats(v);
end

function q = exitRatio(d, x, y, s, a, base)
% Isolation test. Sample the darkening on rings 2.5-4 sigma around the
% centre; a vessel leaving the blob (bend, end, crossing) appears as a peak
% in the angular profile, a microaneurysm has a flat ring. Returned as the
% peak height relative to the blob amplitude.
ang = (0:31) * 2 * pi / 32;
rad = max([2.5 3.25 4] * s, [2.5 3.5 4.5]);
prof = zeros(size(ang));
for r = rad
    prof = prof + netra.util.bilinear(d, x + r * cos(ang), y + r * sin(ang), base);
end
prof = prof / numel(rad);
prof = (prof + circshift(prof, [0 1]) + circshift(prof, [0 -1])) / 3;
q = (max(prof) - median(prof)) / max(a, eps);
end

function tf = onVessel(vmask, x, y, fwhm)
% the candidate sits on a vessel if its centre is vessel and the vessel mask
% continues well beyond the blob (a crossing, bend or bifurcation) - an
% isolated microaneurysm segmented as a small vessel blob is not penalised
D = size(vmask, 1);
if ~vmask(y, x)
    tf = false;
    return
end
R = max(3, ceil(3 * fwhm));
r1 = max(1, y - R); r2 = min(D, y + R);
c1 = max(1, x - R); c2 = min(D, x + R);
[Xw, Yw] = meshgrid(c1:c2, r1:r2);
dist = hypot(Xw - x, Yw - y);
ring = dist >= max(1.5 * fwhm, 2) & dist <= R;
w = vmask(r1:r2, c1:c2);
tf = mean(w(ring)) > 0.2;
end

function [ox, oy] = quadPeak(P)
% sub-pixel offset of the maximum of a 3 x 3 neighbourhood (separable parabola)
dx = (P(2, 3) - P(2, 1)) / 2;
dxx = P(2, 3) - 2 * P(2, 2) + P(2, 1);
dy = (P(3, 2) - P(1, 2)) / 2;
dyy = P(3, 2) - 2 * P(2, 2) + P(1, 2);
ox = 0;
oy = 0;
if dxx < 0
    ox = min(max(-dx / dxx, -0.5), 0.5);
end
if dyy < 0
    oy = min(max(-dy / dyy, -0.5), 0.5);
end
end

function rI = rednessIndex(rgbN, x, y, rad, cfg)
% darkening in red relative to darkening in green: blood absorbs green far
% more than red (~0.3), pigment and shadows darken both channels (~1)
D = size(rgbN, 1);
r1 = max(1, y - rad); r2 = min(D, y + rad);
c1 = max(1, x - rad); c2 = min(D, x + rad);
R1 = max(1, y - 4 * rad - 3); R2 = min(D, y + 4 * rad + 3);
C1 = max(1, x - 4 * rad - 3); C2 = min(D, x + 4 * rad + 3);
t = cfg.enhance.targetRGB;
inR = mean(mean(rgbN(r1:r2, c1:c2, 1))) / t(1);
inG = mean(mean(rgbN(r1:r2, c1:c2, 2))) / t(2);
bgR = median(reshape(rgbN(R1:R2, C1:C2, 1), [], 1)) / t(1);
bgG = median(reshape(rgbN(R1:R2, C1:C2, 2), [], 1)) / t(2);
dR = max(bgR - inR, 0);
dG = max(bgG - inG, 1e-3);
rI = min(dR / dG, 2);
end

function p = score(e, m)
sg = @netra.util.sigmoid;
if e.diameterUm < m.minUm
    sizeTerm = exp(-((m.minUm - e.diameterUm) / 10) ^ 2);
elseif e.diameterUm > m.maxDotUm
    sizeTerm = exp(-((e.diameterUm - m.maxDotUm) / 40) ^ 2);
else
    sizeTerm = 1;
end
p = sg(e.snr, m.minSNR + 1, 0.8) * sg(e.r2, m.minR2 + 0.05, 0.08) * sizeTerm * ...
    sg(e.roundness, m.minRoundness, 0.07) * sg(0.8 - e.redness, 0, 0.12) * ...
    sg(e.amplitude, m.minAmplitude, 0.012) * sg(m.maxExit - e.exitRatio, 0, 0.06);
if e.onVessel
    p = 0.7 * p;
end
end

function list = applyClassifier(list, cfg)
f = fullfile(cfg.paths.models, 'ma_classifier.mat');
if isempty(list) || netra.util.isOctave() || ~exist(f, 'file')
    return
end
S = load(f);
X = [[list.snr]', [list.r2]', [list.diameterUm]', [list.roundness]', ...
     [list.redness]', double([list.onVessel]'), [list.amplitude]'];
[~, post] = predict(S.model, X);
for i = 1:numel(list)
    list(i).prob = post(i, end);
end
end
