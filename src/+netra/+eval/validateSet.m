function R = validateSet(recs, D, V)
%VALIDATESET Diagnostic accuracy of the grader on one test set, STARD-style.
%
%   R = netra.eval.validateSet(recs, D, V)
%     recs  netra.eval.screenDataset output for dataset D (same order)
%     V     what was trained (exp03): variants (fusion models by branch
%           combination), ops (their operating points), fullKey (the
%           deployed combination), threshold (deployed referral threshold)
%
%   Reference standard: referable DR = ICDR grade >= 2 or referable DME, as
%   provided by the dataset (D.referable). Every number comes with its 95 %
%   confidence interval (Wilson for proportions, DeLong for AUC, bootstrap
%   for kappa).
%
%   R.flow        images, reference-ungradable, sent for recapture by the
%                 pipeline, failed, analysed, referable, non-referable
%   R.deployed    the integrated pipeline as deployed:
%                   ai        P(referable) >= threshold (the model alone)
%                   triage    not auto-cleared (REFER, URGENT or
%                             HUMAN_REVIEW) - what the programme acts on
%                   itt       intention to screen: recapture also counts
%                             as not cleared, over every eye with a reference
%                   auc, roc  AUC with DeLong CI; the ROC curve
%                   qwk       five-level quadratic weighted kappa (+ CI),
%                             confusion (5 x 5, rows = reference)
%                   calibration of P(referable): ECE, Brier
%                   conformal coverage and mean set size
%                   triageMix counts; humanReview share
%   R.variants    every trained branch combination on the same eyes: AUC
%                 (DeLong CI, paired DeLong p against the deployed model),
%                 Se / Sp at its own calibrated operating point, exact
%                 McNemar against the deployed model on referable eyes
%                 (sensitivity) and on non-referable eyes (specificity)
%   R.patient     per-patient accuracy (either eye) when patients have
%                 several images, as in Abramoff et al. 2016

n = numel(recs);
ids = {recs.id};
[~, loc] = ismember(ids, D.id);
ref = D.referable(loc);
grade = D.grade(loc);
graded = [recs.graded]';
okRun = [recs.ok]';
triage = {recs.triage}';
recapture = strcmp(triage, 'RECAPTURE');
pRef = [recs.pReferable]';
hasRef = ~isnan(ref);
an = hasRef & graded & isfinite(pRef);
y = ref == 1;

R = struct();
R.name = D.name;
R.flow = struct('images', n, 'referenceUngradable', nnz(~hasRef), 'recapture', nnz(recapture), ...
    'failed', nnz(~okRun), 'analysed', nnz(an), 'referable', nnz(an & y), ...
    'nonReferable', nnz(an & ~y));

% ------------------------------------------------------------ deployed
Dp = struct();
Dp.threshold = V.threshold;
Dp.ai = netra.eval.binaryMetrics(y(an), pRef(an) >= V.threshold);
notCleared = ~strcmp(triage, 'ROUTINE');
Dp.triage = netra.eval.binaryMetrics(y(an), notCleared(an));
itt = hasRef & okRun;
Dp.itt = netra.eval.binaryMetrics(y(itt), notCleared(itt) | recapture(itt));
r = netra.eval.roc(y(an), pRef(an));
Dp.auc = r.auc;
Dp.aucCI = r.aucCI;
Dp.roc = struct('fpr', r.fpr, 'tpr', r.tpr, 'thresholds', r.thresholds);
g = [recs.grade]';
okG = an & ~isnan(grade) & ~isnan(g);
if nnz(okG) > 1
    gt = grade(okG);
    gp = g(okG);
    Dp.qwk = netra.eval.qwk(gt, gp, 5);
    Dp.qwkCI = netra.eval.bootstrap(@(i) netra.eval.qwk(gt(i), gp(i), 5), numel(gt), 'B', 1000);
    Dp.confusion = accumarray([gt + 1, gp + 1], 1, [5 5]);
else
    Dp.qwk = NaN;
    Dp.qwkCI = [NaN NaN NaN];
    Dp.confusion = zeros(5);
end
Dp.calibration = netra.eval.calibration(pRef(an), y(an));
S = vertcat(recs.set);
if any(S(:)) && nnz(okG) > 0
    hit = false(nnz(okG), 1);
    Sg = S(okG, :);
    gg = grade(okG);
    for i = 1:numel(gg)
        hit(i) = Sg(i, gg(i) + 1);
    end
    Dp.conformal = struct('coverage', mean(hit), 'meanSize', mean(sum(Sg, 2)), ...
        'straddle', mean(any(Sg(:, 1:2), 2) & any(Sg(:, 3:5), 2)));
else
    Dp.conformal = struct('coverage', NaN, 'meanSize', NaN, 'straddle', NaN);
end
cats = {'ROUTINE', 'REFER', 'URGENT', 'HUMAN_REVIEW', 'RECAPTURE'};
mix = struct();
for k = 1:numel(cats)
    mix.(cats{k}) = nnz(strcmp(triage, cats{k}));
end
Dp.triageMix = mix;
Dp.humanReview = mix.HUMAN_REVIEW / max(n, 1);
R.deployed = Dp;

% ------------------------------------------------------------ variants
keys = fieldnames(V.variants);
R.variants = struct('key', {}, 'name', {}, 'n', {}, 'auc', {}, 'aucCI', {}, 'pDeLong', {}, ...
    'threshold', {}, 'se', {}, 'seCI', {}, 'sp', {}, 'spCI', {}, 'mcnemarSe', {}, 'mcnemarSp', {});
if ~isempty(keys)
    branches = unique(strsplit(strjoin(keys', '_'), '_'));
    [Bm, okB] = netra.eval.branchMatrix(recs, branches);
    use = an & okB;
    order = [{V.fullKey}; keys(~strcmp(keys, V.fullKey))];
    scores = cell(1, numel(order));
    for k = 1:numel(order)
        P = netra.eval.fusedP(Bm, V.variants.(order{k}));
        scores{k} = sum(P(:, 3:5), 2);
    end
    sc = cellfun(@(s) s(use), scores, 'UniformOutput', false);
    dl = netra.eval.delong(y(use), sc{:});
    fullDec = [];
    for k = 1:numel(order)
        thr = V.threshold;
        if isfield(V.ops, order{k})
            thr = V.ops.(order{k}).threshold;
        end
        dec = scores{k} >= thr;
        m = netra.eval.binaryMetrics(y(use), dec(use));
        v = struct('key', order{k}, 'name', netra.eval.variantName(order{k}, V.fullKey), ...
            'n', nnz(use), 'auc', dl.auc(k), 'aucCI', dl.ci(k, :), 'pDeLong', NaN, ...
            'threshold', thr, 'se', m.se, 'seCI', m.seCI, 'sp', m.sp, 'spCI', m.spCI, ...
            'mcnemarSe', [], 'mcnemarSp', []);
        if k == 1
            fullDec = dec;
        else
            v.pDeLong = dl.p(1, k);
            pos = use & y;
            neg = use & ~y;
            v.mcnemarSe = netra.eval.mcnemar(fullDec(pos), dec(pos));
            v.mcnemarSp = netra.eval.mcnemar(~fullDec(neg), ~dec(neg));
        end
        R.variants(end + 1) = v;
    end
end

% ----------------------------------------------------------- patients
pid = D.patient(loc);
[u, ~, j] = unique(pid);
if numel(u) < n
    np = numel(u);
    pr = NaN(np, 1);
    pd = false(np, 1);
    for p = 1:np
        m = j == p & itt;
        if any(m)
            rr = ref(m);
            pr(p) = double(any(rr == 1));
            pd(p) = any(notCleared(m) | recapture(m));
        end
    end
    ok = ~isnan(pr);
    R.patient = netra.eval.binaryMetrics(pr(ok) == 1, pd(ok));
    R.patient.n = nnz(ok);
end
end
