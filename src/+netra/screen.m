function R = screen(img, varargin)
%SCREEN Screen one fundus photograph for diabetic retinopathy, end to end.
%
%   R = netra.screen('eye.jpg')
%   R = netra.screen(rgb, 'Models', netra.loadModels(cfg), 'Config', cfg, ...
%                    'ID', 'PHC-0042-R', 'Eye', 'R', 'Site', 'PHC Nanded')
%
%   Stages (timings in R.timing):
%     1 quality      FOV, five sub-scores, GRADABLE / ENHANCE / RECAPTURE
%                    with operator feedback; borderline images are enhanced
%                    and re-assessed
%     2 anatomy      vessels, optic disc (measured DD), fovea, ETDRS frame
%     3 lesions      MA (sub-pixel), haemorrhages, exudates/CWS/DME,
%                    NVD/NVE, venous beading, IRMA-like
%     4 grading      ICDR rule engine with evidence, Monte-Carlo rule
%                    distribution, lesion ensemble and CNN when trained,
%                    ordinal fusion, conformal grade set
%     5 explanation  Grad-CAM++ (when a CNN is loaded) or the lesion evidence
%                    map, attention-evidence concordance, Shapley values of
%                    the lesion ensemble
%     6 triage       ROUTINE / REFER / URGENT / HUMAN_REVIEW / RECAPTURE with
%                    reasons, follow-up and a bilingual patient message
%
%   Every component that is not trained or not licensed switches off
%   cleanly; R.models records what produced the grade. With no trained
%   models at all, grading rests on the rule engine alone - transparent,
%   but not validated to the clinical target (see docs/VALIDATION.md).

o = netra.util.opts(struct('Config', [], 'Models', [], 'ID', '', 'Eye', '', ...
    'Site', '', 'Explain', true, 'Verbose', false), varargin{:});
cfg = o.Config;
if isempty(cfg)
    cfg = netra.config();
end
cfg.verbose = o.Verbose;
M = o.Models;
if isempty(M)
    M = netra.loadModels(cfg);
end
if ~isempty(M.vessel)
    cfg.vessels.model = M.vessel;
end
if ~isempty(M.nvNormative)
    cfg.nv.normativeModel = M.nvNormative;
end
if ~isempty(M.calibration) && isfield(M.calibration, 'operatingPoint')
    cfg.grading.referralThreshold = M.calibration.operatingPoint.threshold;
end

R = struct();
R.meta = struct('id', o.ID, 'eye', o.Eye, 'site', o.Site, 'file', '', ...
    'time', datestr(now, 'yyyy-mm-dd HH:MM'), 'version', netra.version());
if ischar(img)
    R.meta.file = img;
    img = netra.io.readFundus(img);
end
rgb = netra.util.toRGB(img);
R.models = M.status;
T0 = tic;

% ------------------------------------------------------------ 1 quality
t = tic;
F = netra.quality.fovMask(rgb);
Q = netra.quality.assess(rgb, cfg, F);
R.timing.quality = toc(t);
R.quality = Q;
R.quality.enhanced = false;
if strcmp(Q.decision, 'RECAPTURE') || ~F.ok
    R = finishRecapture(R, Q, cfg, rgb, T0);
    return
end
t = tic;
S = netra.quality.standardize(rgb, F, cfg.scale.workDiameter);
E = netra.quality.enhance(S, cfg, Q);
if strcmp(Q.decision, 'ENHANCE')
    % re-assess the enhanced image; still borderline -> graded, but human review
    Fe = struct('mask', S.mask, 'centre', S.centre, 'radius', S.radius, ...
        'coverage', Q.fov.coverage, 'clipped', Q.fov.clipped, 'ok', true);
    Q2 = netra.quality.assess(E.rgbN, cfg, Fe);
    Q2.metrics.coverage = Q.metrics.coverage;
    R.quality.afterEnhancement = Q2;
    R.quality.enhanced = true;
    if strcmp(Q2.decision, 'RECAPTURE')
        R = finishRecapture(R, Q, cfg, rgb, T0);
        return
    end
    if strcmp(Q2.decision, 'GRADABLE')
        R.quality.decision = 'GRADABLE';
        R.quality.note = 'Gradable after enhancement';
    end
end
R.timing.enhance = toc(t);
netra.util.say(cfg, 'quality %.2f (%s)', Q.score, R.quality.decision);

% ------------------------------------------------------------ 2 anatomy
t = tic;
A = netra.anatomy.analyze(S, E, cfg);
R.timing.anatomy = toc(t);

% ------------------------------------------------------------ 3 lesions
t = tic;
L = netra.lesions.detectAll(E, A, cfg);
R.timing.lesions = toc(t);

% ------------------------------------------------------------ 4 grading
t = tic;
rules = netra.grading.icdrRules(L.summary, cfg);
branches = struct();
branches.rules = netra.grading.probabilisticRules(L, cfg);
[fx, fnames] = netra.grading.lesionFeatures(L, A, R.quality);
if cfg.grading.useLesionModel && ~isempty(M.lesion)
    branches.lesion = netra.grading.lesionModel('predict', M.lesion, fx);
end
cnnOut = [];
Xcnn = [];
if cfg.grading.useCNN && ~isempty(M.cnn)
    Xcnn = netra.grading.cnn.preprocess(S, cfg);
    cnnOut = netra.grading.cnn.infer(M.cnn, Xcnn, cfg);
    branches.cnn = cnnOut.P;
end
Fz = netra.grading.fuse(branches, M);
sets = [];
if ~isempty(M.calibration) && isfield(M.calibration, 'conformal')
    sets = netra.grading.conformal('predict', Fz.P, M.calibration.conformal);
end
R.timing.grading = toc(t);

% ---------------------------------------------------------- 5 explanation
t = tic;
X = struct('cam', [], 'camMethod', '', 'evidence', netra.xai.evidenceMap(L, A), ...
    'concordance', struct(), 'shapley', []);
if o.Explain && ~isempty(M.cnn)
    try
        cam = netra.xai.gradcam(M.cnn, Xcnn, 'Method', cfg.xai.method);
        X.cam = imresize(cam, size(E.gN), 'bilinear') .* E.mask;
        X.camMethod = cfg.xai.method;
        X.concordance = netra.xai.concordance(X.cam, L.masks, E.mask, cfg);
    catch err
        warning('netra:screen:gradcam', 'Grad-CAM skipped: %s', err.message);
    end
end
if o.Explain && ~isempty(M.lesion)
    X.shapley = netra.grading.lesionModel('explain', M.lesion, fx);
end
R.timing.explain = toc(t);

% ------------------------------------------------------------ 6 triage
Qd = R.quality;
T = netra.grading.decide(Qd, rules, Fz, sets, A, X, cfg);

% ---------------------------------------------------------------- output
R.canvas = struct('rgb', S.rgb, 'display', E.display, 'mask', E.mask, ...
    'scale', S.scale, 'origin', S.origin, 'size', S.size, 'centre', S.centre, 'radius', S.radius);
R.anatomy = struct('od', A.od, 'fovea', A.fovea, 'frame', rmfield(A.frame, ...
    {'distFovea', 'distDisc', 'quadrant', 'zone'}), 'flags', {A.flags}, ...
    'vesselFraction', A.vessels.fraction, 'vesselMask', A.vessels.maskWork);
R.lesions = L;
R.features = struct('values', fx, 'names', {fnames});
R.rules = rules;
R.cnn = cnnOut;
R.fusion = Fz;
R.conformalSet = sets;
R.xai = X;
R.decision = T;
R.overlay = netra.xai.overlay(E.display, A, L);
R.timing.total = toc(T0);
R.cfg = cfg;
R.frameMaps = A.frame;
end

function R = finishRecapture(R, Q, cfg, rgb, T0)
R.decision = netra.grading.decide(Q, struct('dme', 0, 'centreInvolved', false, ...
    'criteria', struct('id', {}, 'met', {})), struct('pReferable', NaN, 'pUrgent', NaN, ...
    'grade', NaN, 'disagreement', 0), [], [], [], cfg);
R.thumbnail = netra.util.imscale(rgb, 512 / max(size(rgb, 1), size(rgb, 2)));
R.timing.total = toc(T0);
R.cfg = cfg;
end
