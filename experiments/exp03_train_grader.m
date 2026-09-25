%EXP03_TRAIN_GRADER Train and calibrate every learned component of the grader.
%
%   Data: APTOS 2019 (3,662 labelled photographs, Aravind Eye Hospital)
%   and the IDRiD grading training set (413). Messidor-2 and the IDRiD
%   test set are never touched here - they are the external validation of
%   exp04.
%
%   APTOS split (grade-stratified, seed 2026, saved to results/exp03):
%     train 70 %   lesion ensemble, CNN weights, rule re-fit (+ IDRiD train)
%     val   10 %   CNN early stopping and softmax temperature
%     fusion 8 %   ordinal fusion of the branches (never seen by a branch)
%     calib  7 %   conformal sets and the referral operating point
%     test   5 %   internal hold-out, scored in exp04
%
%   Steps
%     1  NV normative model from grade-0 training eyes  -> models/nv_normative.mat
%     2  classical pipeline over the training eyes (resumable cache)
%     3  re-fit the single-field 4-2-1 haemorrhage rule (max QWK)
%     4  lesion ensemble, bagged trees on 32 named features  -> models/lesion_model.mat
%        (MATLAB + Statistics and Machine Learning Toolbox)
%     5  CNN, ImageNet backbone fine-tuned with the ordinal loss -> models/netrasetu_cnn.mat
%        (MATLAB R2023b+ with the Deep Learning Toolbox; a GPU is strongly advised)
%     6  branches on the fusion + calib eyes; ordinal fusion of every branch
%        combination (the ablation of exp04)          -> models/fusion.mat
%     7  conformal calibration (alpha = cfg.grading.conformalAlpha) and the
%        operating point with a Wilson-guaranteed sensitivity of 0.90, for
%        the full model and every ablation variant   -> models/calibration.mat
%   Under GNU Octave steps 4-5 are skipped and the grader is the calibrated
%   rule engine; everything else runs.
%
%   Options (set before running): dataAPTOS, dataIDRiD, maxImages (per
%   split, for a quick trial run), cnnEpochs (15), cnnBackbone ('resnet50').

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('netra.config'))
    run(fullfile(root, 'netrasetu_setup.m'));
end
cfg = netra.config();
outDir = fullfile(cfg.paths.results, 'exp03');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
if ~exist(cfg.paths.models, 'dir')
    mkdir(cfg.paths.models);
end
if ~exist('dataAPTOS', 'var'), dataAPTOS = ''; end
if ~exist('dataIDRiD', 'var'), dataIDRiD = ''; end
if ~exist('maxImages', 'var'), maxImages = Inf; end
if ~exist('cnnEpochs', 'var'), cnnEpochs = 15; end
if ~exist('cnnBackbone', 'var'), cnnBackbone = cfg.grading.cnnBackbone; end
octave = netra.util.isOctave();
logFid = fopen(fullfile(outDir, 'training_report.txt'), 'w');
say = @(varargin) netra.util.tee(logFid, varargin{:});

% ------------------------------------------------------------- splits
A = netra.io.aptos(dataAPTOS);
A.split = netra.io.split(A, [0.70 0.10 0.08 0.07 0.05], {'train', 'val', 'fusion', 'calib', 'test'}, 2026);
I = netra.io.idrid(dataIDRiD, 'grading');
It = netra.io.subset(I, find(strcmp(I.split, 'train')));
save(fullfile(outDir, 'splits.mat'), 'A', '-v7');
part = @(s) netra.io.subset(A, find(strcmp(A.split, s)));
cap = @(D) netra.io.subset(D, 1:min(D.n, maxImages));
Dtrain = cap(netra.io.concat(part('train'), It, 'APTOS+IDRiD train'));
Dval = cap(part('val'));
Dfus = cap(part('fusion'));
Dcal = cap(part('calib'));
netra.io.describe(A);
say('Training eyes %d, validation %d, fusion %d, calibration %d\n', Dtrain.n, Dval.n, Dfus.n, Dcal.n);

% --------------------------------------------- 1. NV normative model
M = netra.loadModels(cfg);
M.cnn = []; M.lesion = []; M.fusion = []; M.calibration = [];
nvFile = fullfile(cfg.paths.models, 'nv_normative.mat');
if ~exist(nvFile, 'file')
    g0 = find(Dtrain.grade == 0);
    g0 = g0(1:min(numel(g0), 150));
    say('1  NV normative model from %d grade-0 eyes\n', numel(g0));
    netra.lesions.trainNVNormative(Dtrain.file(g0), cfg, nvFile);
end
M.nvNormative = nvFile;

% ------------------------------------ 2. classical pipeline, training eyes
say('2  classical pipeline over %d training eyes\n', Dtrain.n);
recTrain = netra.eval.screenDataset(Dtrain, 'Models', M, 'Config', cfg, 'Parallel', true, ...
    'Cache', fullfile(outDir, 'classical_train.mat'));
[tf, loc] = ismember({recTrain.id}, Dtrain.id);
yTrain = Dtrain.grade(loc(tf));
good = [recTrain.graded]' & ~isnan(yTrain);
say('   graded %d of %d (%d sent for recapture, %d failed)\n', nnz([recTrain.graded]), ...
    numel(recTrain), nnz(strcmp({recTrain.quality}, 'RECAPTURE')), nnz(~[recTrain.ok]));

% ------------------------------------------------- 3. rule re-fit
best = struct('qwk', -Inf, 'hePerQuadrant', cfg.rules.hePerQuadrant, 'heQuadrants', cfg.rules.heQuadrants);
idx = find(good);
for h = [4 6 8 10 12 15 20]
    for q = 2:4
        c = cfg;
        c.rules.hePerQuadrant = h;
        c.rules.heQuadrants = q;
        g = zeros(numel(idx), 1);
        for k = 1:numel(idx)
            rk = netra.grading.icdrRules(recTrain(idx(k)).summary, c);
            g(k) = rk.grade;
        end
        kappa = netra.eval.qwk(yTrain(idx), g, 5);
        if kappa > best.qwk
            best = struct('qwk', kappa, 'hePerQuadrant', h, 'heQuadrants', q);
        end
    end
end
rulesFit = struct('hePerQuadrant', best.hePerQuadrant, 'heQuadrants', best.heQuadrants);
cfg.rules.hePerQuadrant = best.hePerQuadrant;
cfg.rules.heQuadrants = best.heQuadrants;
say('3  single-field 4-2-1 rule: > %d haemorrhages in >= %d quadrants (rule-engine QWK %.3f on training eyes)\n', ...
    best.hePerQuadrant, best.heQuadrants, best.qwk);

% ------------------------------------------------ 4. lesion ensemble
branches = {'rules'};
if ~octave && netra.util.has('fitcensemble')
    X = vertcat(recTrain(good).features);
    [~, names] = netra.grading.lesionFeatures();
    model = netra.grading.lesionModel('train', X, yTrain(good), names, 'KFold', 5);
    save(fullfile(cfg.paths.models, 'lesion_model.mat'), 'model', '-v7.3');
    oofGrade = sum(cumsum(model.oof, 2) < 0.5, 2);
    say('4  lesion ensemble: out-of-fold QWK %.3f on %d eyes\n', ...
        netra.eval.qwk(yTrain(good), oofGrade, 5), nnz(good));
    M.lesion = model;
    branches{end + 1} = 'lesion';
else
    say('4  lesion ensemble skipped (needs MATLAB + Statistics and Machine Learning Toolbox)\n');
end

% --------------------------------------------------------------- 5. CNN
if ~octave && netra.util.has('trainnet')
    cacheDir = fullfile(outDir, 'cnn_cache');
    fTr = netra.grading.cnn.cacheDataset(Dtrain.file, cfg, cacheDir, 'Parallel', true);
    fVa = netra.grading.cnn.cacheDataset(Dval.file, cfg, cacheDir, 'Parallel', true);
    okT = ~cellfun(@isempty, fTr) & ~isnan(Dtrain.grade);
    okV = ~cellfun(@isempty, fVa) & ~isnan(Dval.grade);
    model = netra.grading.cnn.train(fTr(okT), Dtrain.grade(okT), fVa(okV), Dval.grade(okV), cfg, ...
        'Backbone', cnnBackbone, 'Epochs', cnnEpochs, 'Checkpoint', fullfile(outDir, 'cnn_checkpoints'));
    save(fullfile(cfg.paths.models, 'netrasetu_cnn.mat'), 'model', '-v7.3');
    vg = sum(cumsum(netra.util.softmax(model.valLogits / model.temperature), 2) < 0.5, 2);
    say('5  CNN (%s): validation QWK %.3f, temperature %.2f\n', cnnBackbone, ...
        netra.eval.qwk(model.valGrades, vg, 5), model.temperature);
    M.cnn = model;
    branches = [{'cnn'}, branches];
else
    say('5  CNN skipped (needs MATLAB R2023b+ with the Deep Learning Toolbox)\n');
end

% ------------------------------------------------------------ 6. fusion
Dfc = netra.io.concat(Dfus, Dcal, 'fusion+calib');
say('6  branches on %d fusion and calibration eyes\n', Dfc.n);
recFC = netra.eval.screenDataset(Dfc, 'Models', M, 'Config', cfg, 'Parallel', true, ...
    'Cache', fullfile(outDir, 'branches_fusion_calib.mat'));
[tf, loc] = ismember({recFC.id}, Dfc.id);
yFC = Dfc.grade(loc(tf));
refFC = Dfc.referable(loc(tf));
isFus = ismember({recFC.id}', Dfus.id);
[Bm, okB] = netra.eval.branchMatrix(recFC, branches);
combos = {};
for k = 1:numel(branches)                            % every non-empty subset
    combos = [combos, num2cell(nchoosek(1:numel(branches), k), 2)']; %#ok<AGROW>
end
variants = struct();
for c = 1:numel(combos)
    b = branches(combos{c});
    key = strjoin(b, '_');
    use = isFus & okB & ~isnan(yFC);
    Bc = struct();
    for k = 1:numel(b)
        Bc.(b{k}) = Bm.(b{k})(use, :);
    end
    % unweighted, so the fused probabilities stay calibrated to the
    % training case mix (the referral threshold is chosen separately)
    variants.(key) = netra.grading.trainFusion(Bc, yFC(use), 'Branches', b);
    say('   fusion %-20s fitted on %d eyes\n', key, nnz(use));
end
fullKey = strjoin(branches, '_');
fusion = variants.(fullKey);
save(fullfile(cfg.paths.models, 'fusion.mat'), 'fusion', 'variants', '-v7');

% ------------------------------------------------------- 7. calibration
use = ~isFus & okB & ~isnan(yFC);
say('7  calibration on %d eyes (%d referable)\n', nnz(use), nnz(refFC(use) == 1));
ops = struct();
keysV = fieldnames(variants);
for k = 1:numel(keysV)
    Pv = netra.eval.fusedP(Bm, variants.(keysV{k}));
    pr = sum(Pv(use, 3:5), 2);
    ops.(keysV{k}) = netra.grading.operatingPoint(pr, refFC(use) == 1, 'Target', 0.90);
end
Pf = netra.eval.fusedP(Bm, fusion);
conf = netra.grading.conformal('calibrate', Pf(use, :), yFC(use), cfg.grading.conformalAlpha);
op = ops.(fullKey);
calibration = struct('conformal', conf, 'operatingPoint', op, 'rules', rulesFit, ...
    'variants', ops, 'branches', {branches}, 'nCalibration', nnz(use), ...
    'created', datestr(now, 'yyyy-mm-dd HH:MM'));
save(fullfile(cfg.paths.models, 'calibration.mat'), 'calibration', '-v7');
say(['   operating point: P(referable) >= %.3f gives sensitivity %.3f (95%% CI %.3f-%.3f), ' ...
    'specificity %.3f on the calibration eyes\n'], op.threshold, op.se, op.seCI(1), op.seCI(2), op.sp);
fclose(logFid);
fprintf('Models written to %s\n', cfg.paths.models);
