function Q = assess(rgb, cfg, F)
%ASSESS Decide whether a fundus photograph is gradable - and if not, why.
%
%   Q = netra.quality.assess(rgb)
%   Q = netra.quality.assess(rgb, cfg, F)     reuse a computed FOV (fovMask)
%
%   Five interpretable sub-scores in [0, 1] mirror what a human grader checks:
%
%     field         how much of the aperture disc is actually in the frame
%     focus         scale-ratio sharpness of vessel edges, penalised by noise
%                   (a Gaussian-blurred edge loses fine-scale gradient faster
%                   than coarse-scale gradient; the ratio is independent of
%                   illumination and contrast)
%     illumination  exposure level, under-/over-exposed area, uniformity
%     contrast      vessel contrast of the illumination-normalised green
%                   channel (drops with haze, cataract and dirty optics)
%     artifact      lid/lash shadow and corneal reflection arcs
%
%   The overall score Q is their weighted geometric mean, so one failed
%   criterion cannot be averaged away. Decision:
%     'GRADABLE'   Q >= cfg.quality.gradable
%     'ENHANCE'    between the two thresholds: enhance, re-assess, and route
%                  to a human reader if still borderline
%     'RECAPTURE'  Q < cfg.quality.recapture, or less than
%                  cfg.quality.minCoverage of the field is visible
%   Q.feedback lists actionable instructions for the camera operator
%   (English and Hindi), worst problem first.

if nargin < 2 || isempty(cfg)
    cfg = netra.config();
end
if nargin < 3 || isempty(F)
    F = netra.quality.fovMask(rgb);
end
q = cfg.quality;
D = cfg.scale.anatomyDiameter;

Q = struct('score', 0, 'decision', 'RECAPTURE', 'worst', 0, 'sub', struct(), ...
    'metrics', struct(), 'components', struct(), ...
    'feedback', struct('key', {}, 'en', {}, 'hi', {}, 'severity', {}), 'fov', F);
if ~F.ok
    Q.sub = struct('field', 0, 'focus', 0, 'illumination', 0, 'contrast', 0, 'artifact', 0);
    Q.feedback = addFeedback(Q.feedback, 'fb.field', 1);
    return
end

S = netra.quality.standardize(rgb, F, D);
[Xc, Yc] = meshgrid(1:D, 1:D);
rr = hypot(Xc - S.centre(1), Yc - S.centre(2)) / S.radius;
mask = S.mask & rr <= 0.97;
inner = mask & rr <= 0.90;
R = S.rgb(:, :, 1); G = S.rgb(:, :, 2); B = S.rgb(:, :, 3);
L = 0.299 * R + 0.587 * G + 0.114 * B;
M = struct();

% ---------------------------------------------------------- illumination
BL = netra.util.maskedSmooth(L, mask, 0.08 * D);
medBL = median(BL(mask));
M.meanLuma = mean(L(mask));
M.darkFrac = mean(BL(mask) < max(0.045, q.darkLevel * medBL));
% saturation is judged on green: a clipped red channel is common in lightly
% pigmented fundi and does not hide lesions, a clipped green channel does
M.brightFrac = mean(G(mask) >= q.saturation | L(mask) >= 0.95);
p = netra.util.pct(BL(mask), [10 90]);
M.uniformity = 1 - (p(2) - p(1)) / max(p(2) + p(1), eps);

% ------------------------------------------------ contrast, focus, noise
BG = netra.quality.background(G, mask, cfg.enhance.backgroundDD * cfg.scale.ddPerFOV * 2 * S.radius);
gN = G ./ BG;
dk = 1 - imgaussfilt(gN, 1.0);
pc = netra.util.pct(dk(mask), [50 97]);
M.contrast = pc(2) - pc(1);
% focus: ratio of Laplacian-of-Gaussian energy at sigma = 1 and 2 px. Defocus
% attenuates the finer band first; the ratio is insensitive to exposure and
% contrast and, across phantoms and real photographs, to the lesion load.
lap = fspecial('laplacian', 0);
l1 = imfilter(imgaussfilt(gN, 1.0), lap, 'replicate');
l2 = imfilter(imgaussfilt(gN, 2.0), lap, 'replicate');
ratio = sqrt(mean(l1(inner) .^ 2) / max(mean(l2(inner) .^ 2), eps));
M.focusRatio = ratio;
M.focusIndex = min(max((ratio - 1) / 1.4, 0), 1);
M.noise = netra.quality.noiseSigma(gN, inner);

% -------------------------------------------------------------- artefacts
top = mask & (Yc - S.centre(2)) < -0.45 * S.radius;
bot = mask & (Yc - S.centre(2)) > 0.45 * S.radius;
shadowTop = mean(BL(top) < 0.45 * medBL);
shadowBot = mean(BL(bot) < 0.45 * medBL);
if ~any(top(:)), shadowTop = 0; end
if ~any(bot(:)), shadowBot = 0; end
M.lashFrac = max(shadowTop, shadowBot);
ring = mask & rr > 0.78;
if any(ring(:))
    M.flareFrac = mean(BL(ring) > 1.35 * median(BL(ring)));
else
    M.flareFrac = 0;
end
% aperture area lost to the photograph frame (decentred / cropped capture)
% versus area inside the frame that is too dark to see (lid, lashes, pupil)
inFrame = S.circle & frameMask(S);
M.frameCoverage = nnz(inFrame) / max(nnz(S.circle), 1);
M.shadowFrac = nnz(inFrame & ~S.mask) / max(nnz(S.circle), 1);
M.coverage = min(F.coverage, 1);

% -------------------------------------------------------------- sub-scores
sg = @netra.util.sigmoid;
sub = struct();
sub.field = sg(M.frameCoverage, q.minCoverage + 0.05, 0.05);
noiseTerm = sg(q.noiseCenter - M.noise, 0, q.noiseWidth);
sub.focus = sg(M.focusIndex, q.focusCenter, q.focusWidth) * noiseTerm;
lumaTerm = sg(M.meanLuma, q.lumaCenter, q.lumaWidth);
darkTerm = sg(q.darkMaxFrac - M.darkFrac, 0, 0.06);
brightTerm = sg(q.brightMaxFrac - M.brightFrac, 0, 0.02);
unifTerm = sg(M.uniformity, q.uniformityMin, q.uniformityWidth);
sub.illumination = lumaTerm * darkTerm * brightTerm * unifTerm;
sub.contrast = sg(M.contrast, q.contrastCenter, q.contrastWidth);
sub.artifact = sg(0.18 - M.lashFrac, 0, 0.05) * sg(0.10 - M.flareFrac, 0, 0.035) * ...
    sg(q.shadowMax - M.shadowFrac, 0, 0.035);

w = q.weights;
names = fieldnames(w);
num = 0;
den = 0;
for k = 1:numel(names)
    num = num + w.(names{k}) * log(max(sub.(names{k}), 1e-3));
    den = den + w.(names{k});
end
Q.score = exp(num / den);
Q.sub = sub;
Q.metrics = M;
Q.components = struct('noise', noiseTerm, 'luma', lumaTerm, 'dark', darkTerm, ...
    'bright', brightTerm, 'uniformity', unifTerm);

subs = struct2cell(sub);
worst = min([subs{:}]);
Q.worst = worst;
if Q.score >= q.gradable && worst >= q.minSubscore
    Q.decision = 'GRADABLE';
elseif Q.score >= q.recapture && worst >= q.failSubscore
    Q.decision = 'ENHANCE';
else
    Q.decision = 'RECAPTURE';
end
if M.coverage < q.minCoverage
    Q.decision = 'RECAPTURE';
end

% ----------------------------------------------------- operator feedback
fb = Q.feedback;
if sub.field < 0.5
    fb = addFeedback(fb, 'fb.field', 1 - sub.field);
end
if sub.focus < 0.5
    if noiseTerm < 0.5 && lumaTerm < 0.5
        fb = addFeedback(fb, 'fb.dark', 1 - sub.focus);
    else
        fb = addFeedback(fb, 'fb.blur', 1 - sub.focus);
    end
end
if sub.illumination < 0.5
    if brightTerm < min([lumaTerm darkTerm unifTerm])
        fb = addFeedback(fb, 'fb.bright', 1 - sub.illumination);
    else
        fb = addFeedback(fb, 'fb.dark', 1 - sub.illumination);
    end
end
if sub.contrast < 0.5
    fb = addFeedback(fb, 'fb.contrast', 1 - sub.contrast);
end
if sub.artifact < 0.5
    fb = addFeedback(fb, 'fb.artifact', 1 - sub.artifact);
end
if ~isempty(fb)
    [~, order] = sort([fb.severity], 'descend');
    fb = fb(order);
    [~, keep] = unique({fb.key}, 'first');
    fb = fb(sort(keep));
end
Q.feedback = fb;
end

function m = frameMask(S)
% canvas pixels that fall inside the original photograph
[Xc, Yc] = meshgrid(1:size(S.mask, 2), 1:size(S.mask, 1));
xo = (Xc - 1) / S.scale + S.origin(1);
yo = (Yc - 1) / S.scale + S.origin(2);
m = xo >= 0.5 & yo >= 0.5 & xo <= S.size(2) + 0.5 & yo <= S.size(1) + 0.5;
end

function fb = addFeedback(fb, key, severity)
fb(end + 1) = struct('key', key, 'en', netra.util.i18n(key, 'en'), ...
    'hi', netra.util.i18n(key, 'hi'), 'severity', severity);
end
