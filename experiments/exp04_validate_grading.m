%EXP04_VALIDATE_GRADING Clinical validation of referable-DR screening on held-out data.
%
%   Questions
%     1. Does the integrated pipeline reach the programme target for
%        referable DR (ICDR grade >= 2 or referable DME): sensitivity
%        > 0.90 and specificity > 0.85?
%     2. Does integration beat every technique alone on the SAME eyes?
%        (paired DeLong test of AUC; exact McNemar of the referral decision
%        on referable and on non-referable eyes, each variant at its own
%        operating point chosen on the calibration split)
%     3. Are its probabilities and conformal sets trustworthy (calibration
%        error, coverage), and how much work goes to a human?
%
%   Test sets - none used for training, fusion or calibration (exp03):
%     APTOS hold-out   5 % of APTOS 2019 (internal validation)
%     IDRiD test       103 images, Nanded, India (external to APTOS)
%     Messidor-2       1,748 images of 874 patients, France (external:
%                      other population, camera and graders); per-patient
%                      results as in Abramoff et al. 2016
%   The operating point was fixed on the calibration split BEFORE any of
%   these images was screened (models/calibration.mat).
%
%   Outputs (results/exp04): <set>_records.mat (every eye, resumable),
%   summary.mat, validation.csv, roc_<set>.png, roc_referable.csv (the
%   external ROC, read by exp06 to plan the district), stard.txt.
%   Options: dataIDRiD, dataMessidor2, maxImages.

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('netra.config'))
    run(fullfile(root, 'netrasetu_setup.m'));
end
cfg = netra.config();
outDir = fullfile(cfg.paths.results, 'exp04');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
if ~exist('dataIDRiD', 'var'), dataIDRiD = ''; end
if ~exist('dataMessidor2', 'var'), dataMessidor2 = ''; end
if ~exist('maxImages', 'var'), maxImages = Inf; end

M = netra.loadModels(cfg);
V = struct('variants', struct(), 'ops', struct(), 'fullKey', 'rules', ...
    'threshold', cfg.grading.referralThreshold);
fusFile = fullfile(cfg.paths.models, 'fusion.mat');
if exist(fusFile, 'file') && ~isempty(M.calibration)
    S = load(fusFile);
    V.variants = S.variants;
    V.ops = M.calibration.variants;
    V.fullKey = strjoin(M.calibration.branches, '_');
    V.threshold = M.calibration.operatingPoint.threshold;
    fprintf('Deployed model: %s, referral threshold P(referable) >= %.3f (fixed on %d calibration eyes)\n', ...
        netra.eval.variantName(V.fullKey, V.fullKey), V.threshold, M.calibration.nCalibration);
else
    warning('netra:exp04:uncalibrated', ['No trained fusion / calibration in models/: validating ' ...
        'the uncalibrated rule engine (run exp03 first for the full pipeline).']);
end

% ------------------------------------------------------------ test sets
sets = {};
splitFile = fullfile(cfg.paths.results, 'exp03', 'splits.mat');
if exist(splitFile, 'file')
    S = load(splitFile);
    sets(end + 1, :) = {'aptos', 'APTOS 2019 hold-out', netra.io.subset(S.A, find(strcmp(S.A.split, 'test')))};
else
    fprintf('APTOS hold-out skipped: results/exp03/splits.mat not found (run exp03).\n');
end
try
    I = netra.io.idrid(dataIDRiD, 'grading');
    sets(end + 1, :) = {'idrid', 'IDRiD test', netra.io.subset(I, find(strcmp(I.split, 'test')))};
catch err
    fprintf('IDRiD skipped: %s\n', err.message);
end
try
    sets(end + 1, :) = {'messidor2', 'Messidor-2', netra.io.messidor2(dataMessidor2)};
catch err
    fprintf('Messidor-2 skipped: %s\n', err.message);
end
if isempty(sets)
    error('netra:exp04:noData', 'No test set found. See data/README.md.');
end

results = struct();
stard = fopen(fullfile(outDir, 'stard.txt'), 'w');
csv = fopen(fullfile(outDir, 'validation.csv'), 'w');
fprintf(csv, ['set,variant,n,referable,auc,aucLo,aucHi,pDeLongVsDeployed,threshold,se,seLo,seHi,' ...
    'sp,spLo,spHi,mcnemarSeP,mcnemarSpP\n']);
for s = 1:size(sets, 1)
    key = sets{s, 1};
    Dset = sets{s, 3};
    Dset = netra.io.subset(Dset, 1:min(Dset.n, maxImages));
    fprintf('\n==== %s (%d images)\n', sets{s, 2}, Dset.n);
    recs = netra.eval.screenDataset(Dset, 'Models', M, 'Config', cfg, 'Parallel', true, ...
        'Explain', false, 'Cache', fullfile(outDir, [key '_records.mat']));
    R = netra.eval.validateSet(recs, Dset, V);
    R.label = sets{s, 2};
    results.(key) = R;

    f = R.flow;
    msg = sprintf(['%s: %d images; %d without a reference grade (ungradable per reference); ' ...
        '%d sent for recapture by the pipeline; %d failed; %d analysed (%d referable, %d not)\n'], ...
        R.label, f.images, f.referenceUngradable, f.recapture, f.failed, f.analysed, ...
        f.referable, f.nonReferable);
    fprintf('%s', msg);
    fprintf(stard, '%s', msg);
    Dp = R.deployed;
    fprintf('  %-34s Se %5.1f%% (%4.1f-%4.1f)   Sp %5.1f%% (%4.1f-%4.1f)\n', ...
        'model alone, P >= threshold', 100 * Dp.ai.se, 100 * Dp.ai.seCI, 100 * Dp.ai.sp, 100 * Dp.ai.spCI);
    fprintf('  %-34s Se %5.1f%% (%4.1f-%4.1f)   Sp %5.1f%% (%4.1f-%4.1f)\n', ...
        'triage: not auto-cleared', 100 * Dp.triage.se, 100 * Dp.triage.seCI, 100 * Dp.triage.sp, ...
        100 * Dp.triage.spCI);
    fprintf('  %-34s Se %5.1f%% (%4.1f-%4.1f)   Sp %5.1f%% (%4.1f-%4.1f)\n', ...
        'intention to screen', 100 * Dp.itt.se, 100 * Dp.itt.seCI, 100 * Dp.itt.sp, 100 * Dp.itt.spCI);
    fprintf('  AUC %.3f (%.3f-%.3f)   QWK %.3f (%.3f-%.3f)   ECE %.3f   Brier %.3f\n', Dp.auc, ...
        Dp.aucCI, Dp.qwk, Dp.qwkCI(1:2), Dp.calibration.ece, Dp.calibration.brier);
    fprintf('  conformal sets: coverage %.3f (target %.2f), mean size %.2f grades\n', ...
        Dp.conformal.coverage, 1 - cfg.grading.conformalAlpha, Dp.conformal.meanSize);
    mix = Dp.triageMix;
    fprintf('  triage: ROUTINE %d  REFER %d  URGENT %d  HUMAN_REVIEW %d  RECAPTURE %d\n', ...
        mix.ROUTINE, mix.REFER, mix.URGENT, mix.HUMAN_REVIEW, mix.RECAPTURE);
    if isfield(R, 'patient')
        p = R.patient;
        fprintf('  per patient (%d): Se %.1f%% (%.1f-%.1f)  Sp %.1f%% (%.1f-%.1f)\n', p.n, 100 * p.se, ...
            100 * p.seCI, 100 * p.sp, 100 * p.spCI);
    end
    if ~isempty(R.variants)
        fprintf('\n  %-32s %6s %17s %9s %20s %20s %11s %11s\n', 'same eyes, each at its own threshold', ...
            'AUC', '95% CI', 'DeLong p', 'Se (95% CI)', 'Sp (95% CI)', 'McNemar Se', 'McNemar Sp');
        for k = 1:numel(R.variants)
            v = R.variants(k);
            pS = '';
            pP = '';
            if ~isempty(v.mcnemarSe)
                pS = sprintf('p = %.2g', v.mcnemarSe.p);
                pP = sprintf('p = %.2g', v.mcnemarSp.p);
            end
            fprintf('  %-32s %6.3f   %.3f-%.3f %9.2g   %5.1f (%4.1f-%4.1f)   %5.1f (%4.1f-%4.1f) %11s %11s\n', ...
                v.name, v.auc, v.aucCI, v.pDeLong, 100 * v.se, 100 * v.seCI, 100 * v.sp, 100 * v.spCI, pS, pP);
            mSe = NaN; mSp = NaN;
            if ~isempty(v.mcnemarSe)
                mSe = v.mcnemarSe.p;
                mSp = v.mcnemarSp.p;
            end
            fprintf(csv, '%s,%s,%d,%d,%.5f,%.5f,%.5f,%.4g,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.4g,%.4g\n', ...
                key, v.key, v.n, f.referable, v.auc, v.aucCI, v.pDeLong, v.threshold, v.se, v.seCI, ...
                v.sp, v.spCI, mSe, mSp);
        end
    end
    % ROC figure: deployed first, then the single techniques
    try
        curves = struct('name', {}, 'fpr', {}, 'tpr', {}, 'auc', {}, 'aucCI', {});
        curves(1) = struct('name', netra.eval.variantName(V.fullKey, V.fullKey), 'fpr', Dp.roc.fpr, ...
            'tpr', Dp.roc.tpr, 'auc', Dp.auc, 'aucCI', Dp.aucCI);
        [Bm, okB] = netra.eval.branchMatrix(recs, {'cnn', 'lesion', 'rules'});
        [~, loc] = ismember({recs.id}, Dset.id);
        yv = Dset.referable(loc) == 1;
        anv = ~isnan(Dset.referable(loc)) & [recs.graded]';
        for b = {'cnn', 'lesion', 'rules'}
            if isfield(V.variants, b{1}) && ~strcmp(b{1}, V.fullKey)
                P = netra.eval.fusedP(Bm, V.variants.(b{1}));
                use = anv & all(isfinite(Bm.(b{1})), 2);
                r = netra.eval.roc(yv(use), sum(P(use, 3:5), 2));
                curves(end + 1) = struct('name', netra.eval.variantName(b{1}), 'fpr', r.fpr, ...
                    'tpr', r.tpr, 'auc', r.auc, 'aucCI', r.aucCI); %#ok<SAGROW>
            end
        end
        bench = [];
        if strcmp(key, 'messidor2')
            bench = struct('name', {'Gulshan 2016', 'IDx-DR 2016 (per patient)', 'IDP 2013 (per patient)'}, ...
                'se', {0.961, 0.968, 0.968}, 'sp', {0.939, 0.870, 0.594});
        end
        op = [1 - Dp.ai.sp, Dp.ai.se];
        netra.eval.plotROC(curves, 'Title', sprintf('%s: referable diabetic retinopathy', R.label), ...
            'File', fullfile(outDir, ['roc_' key '.png']), 'Operating', op, 'Benchmarks', bench);
        close all
    catch err
        fprintf('  (ROC figure skipped: %s)\n', err.message);
    end
end
fclose(csv);
fclose(stard);

% the external ROC feeds the district simulation (exp06)
ext = '';
for k = {'messidor2', 'idrid', 'aptos'}
    if isfield(results, k{1})
        ext = k{1};
        break
    end
end
r = results.(ext).deployed.roc;
fid = fopen(fullfile(outDir, 'roc_referable.csv'), 'w');
fprintf(fid, 'threshold,fpr,tpr\n');
fprintf(fid, '%.6g,%.6f,%.6f\n', [min(r.thresholds, 1e6), r.fpr, r.tpr]');
fclose(fid);
save(fullfile(outDir, 'summary.mat'), 'results', '-v7');

fprintf('\nPublished referable-DR results (context: other data, reference standards and definitions):\n');
netra.eval.benchmarks('Task', 'referable-dr');
netra.eval.benchmarks('Task', 'standard');
fprintf('Saved %s\n', outDir);
