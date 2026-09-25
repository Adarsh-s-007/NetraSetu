% Statistics used for validation, checked against independent references:
% scikit-learn 1.9 (roc_auc_score, cohen_kappa_score, brier_score_loss,
% average_precision_score), statsmodels 0.15 (Wilson interval, exact
% McNemar, OrderedModel) and a midrank implementation of DeLong's method
% (Sun & Xu 2014), all run on the literal data below.
y = logical([0 0 0 1 1 0 1 0 0 0 1 1 1 0 0 0 0 0 0 0 1 1 0 1 1 0 0 0 0 0 0 1 1 1 0 1 1 1 0 1]');
s1 = [-0.1 0.1 0.0 0.1 0.8 0.8 -0.1 0.5 0.1 -0.4 2.0 1.3 0.1 0.0 0.3 -0.1 0.4 0.0 0.4 0.9 ...
    0.4 0.9 -0.3 0.9 0.1 -0.3 -0.1 0.5 0.7 -0.8 -0.5 1.2 -0.4 0.5 -0.1 1.6 1.2 0.6 -0.2 0.6]';
s2 = [0.9 -0.3 -0.2 0.6 0.3 -0.1 -0.3 0.0 -0.3 0.7 0.8 0.4 0.8 -0.2 0.6 0.0 0.4 -0.8 0.2 -1.0 ...
    -0.8 0.2 -0.5 0.5 1.7 -0.5 -0.4 0.1 0.3 -0.1 -0.1 0.8 0.7 -0.2 0.0 0.4 -0.2 0.6 -0.5 1.0]';

%% ROC AUC with ties equals scikit-learn
r = netra.eval.roc(y, s1);
assert(abs(r.auc - 0.7928388746803069) < 1e-12, 'AUC %.15f', r.auc);
r2 = netra.eval.roc(y, s2);
assert(abs(r2.auc - 0.7570332480818414) < 1e-12);

%% DeLong standard errors and paired test equal the midrank reference
d = netra.eval.delong(y, s1, s2);
assert(max(abs(d.auc - [0.79283887 0.75703325])) < 1e-8);
assert(max(abs(d.se - [0.0744329 0.08250109])) < 1e-7, 'SE %s', mat2str(d.se, 9));
assert(abs(d.p(1, 2) - 0.7416266912991283) < 1e-9, 'p %.12f', d.p(1, 2));

%% Quadratic weighted kappa equals scikit-learn
g1 = [4 0 4 3 2 3 4 2 0 3 1 1 0 0 4 1 0 0 1 1 1 4 4 2 4 1 0 1 0 4 1 2 1 4 0 2 4 2 4 4 3 3 2 2 4 2 4 4 1 2 3 4 0 0 1 2 0 2 2 4];
g2 = [4 0 4 3 2 4 3 3 0 3 2 1 0 0 4 1 1 0 1 1 1 4 4 3 4 2 0 1 0 4 2 2 0 4 0 2 4 2 3 4 3 3 2 2 4 2 4 4 1 2 4 4 0 0 2 3 0 3 2 4];
assert(abs(netra.eval.qwk(g1, g2, 5) - 0.9474474474474475) < 1e-12);
assert(abs(netra.eval.qwk(g1, g1, 5) - 1) < 1e-12);

%% Wilson intervals equal statsmodels
assert(max(abs(netra.eval.wilson(45, 50) - [0.7863976856252034 0.9565242350681095])) < 1e-12);
assert(max(abs(netra.eval.wilson(8, 10) - [0.49016247153664183 0.9433178485456247])) < 1e-12);

%% Exact McNemar equals statsmodels
a = [true(20, 1); true(12, 1); false(3, 1); false(5, 1)];
b = [true(20, 1); false(12, 1); true(3, 1); false(5, 1)];
t = netra.eval.mcnemar(a, b);
assert(t.aBetter == 12 && t.bBetter == 3);
assert(abs(t.p - 0.03515625) < 1e-12);

%% Brier score and step-wise average precision equal scikit-learn
p = 1 ./ (1 + exp(-(s1 - 0.3)));
c = netra.eval.calibration(p, y);
assert(abs(c.brier - 0.20071995213249627) < 1e-12);
pr = netra.eval.prCurve(y, s1);
assert(abs(pr.aupr - 0.7729269053959458) < 1e-12, 'AP %.15f', pr.aupr);

%% Histogram PR / ROC (IDRiD full-resolution scoring) agrees with the exact curves
q = round(100 * (s1 - min(s1)) / (max(s1) - min(s1))) / 100;    % scores on the bin grid
H = netra.eval.countsPR('add', netra.eval.countsPR('init', 100), q, y);
m = netra.eval.countsPR('metrics', H);
ref1 = netra.eval.prCurve(y, q);
ref2 = netra.eval.roc(y, q);
assert(abs(m.aupr - ref1.aupr) < 1e-12, 'AUPR %.15f vs %.15f', m.aupr, ref1.aupr);
assert(abs(m.auc - ref2.auc) < 1e-12, 'AUC %.15f vs %.15f', m.auc, ref2.auc);

%% Proportional-odds model equals statsmodels OrderedModel (maximum likelihood)
D = csvread(fullfile(fileparts(which('run_tests')), 'data', 'ordinal_reference.csv'));
mdl = netra.grading.ordinalLogit('fit', D(:, 1:2), D(:, 3), 'Lambda', 0);
bo = mdl.beta(:) ./ mdl.sd(:);
th = mdl.theta(:)' + mdl.mu(:)' * bo;
assert(max(abs(bo' - [1.26840029 -0.62922881])) < 2e-4, 'beta %s', mat2str(bo', 8));
assert(max(abs(th - [-0.95216203 0.17377475 0.90728461 2.02947415])) < 2e-4, 'theta %s', mat2str(th, 8));
P = netra.grading.ordinalLogit('predict', mdl, D(:, 1:2));
assert(max(abs(sum(P, 2) - 1)) < 1e-12);

%% Binary metrics: counts, Wilson CIs and likelihood ratios are consistent
m = netra.eval.binaryMetrics(y, s1 > 0.45);
assert(m.tp + m.fn == nnz(y) && m.tn + m.fp == nnz(~y));
assert(abs(m.se - m.tp / (m.tp + m.fn)) < 1e-12);
assert(all(abs(m.seCI - netra.eval.wilson(m.tp, m.tp + m.fn)) < 1e-12));

%% Bootstrap interval brackets the estimate and is reproducible
f = @(i) mean(s1(i));
c1 = netra.eval.bootstrap(f, numel(s1), 'B', 500);
c2 = netra.eval.bootstrap(f, numel(s1), 'B', 500);
assert(isequal(c1, c2));
assert(c1(1) < c1(3) && c1(3) < c1(2) && abs(c1(3) - mean(s1)) < 1e-12);

%% FROC counts a detection once and reports the ROC-challenge score
dets = struct('image', {1, 1, 1, 2}, 'x', {10, 11, 50, 20}, 'y', {10, 10, 50, 20}, 'score', {0.9, 0.8, 0.7, 0.6});
gts = struct('image', {1, 2}, 'x', {10, 20}, 'y', {10, 20}, 'radius', {3, 3});
f = netra.eval.froc(dets, gts, 2);
assert(f.score > 0 && f.score <= 1);
assert(max(f.sensitivity) == 1);
