function Fz = fuse(branches, models)
%FUSE Combine the CNN, lesion-model and rule-engine grade distributions.
%
%   Fz = netra.grading.fuse(branches, models)
%     branches.cnn     1 x 5 calibrated CNN probabilities (or [])
%     branches.lesion  1 x 5 lesion-ensemble probabilities (or [])
%     branches.rules   1 x 5 Monte-Carlo rule-engine probabilities
%     models.fusion    ordinal model from netra.grading.trainFusion (or [])
%
%   With a trained fusion model the branches enter a proportional-odds
%   model as cumulative logits, logit P(grade >= k), k = 1..4 - the stacking
%   layer learns how much to trust each branch at each severity boundary
%   and is itself interpretable (one slope per branch and boundary).
%   Without one, a logarithmic opinion pool is used,
%       P ~ prod_b P_b ^ w_b   (w: CNN 0.5, lesions 0.3, rules 0.2),
%   renormalised over the branches that are available.
%
%   Fz fields: P (1 x 5), grade (ordinal median, which minimises the
%   expected absolute grade error), expected (mean grade), pReferable
%   (P(grade >= 2)), pUrgent (P(grade = 4)), entropy, disagreement (max
%   difference in grades between branches), branches (as given), method.

names = {'cnn', 'lesion', 'rules'};
avail = {};
for k = 1:numel(names)
    if isfield(branches, names{k}) && ~isempty(branches.(names{k}))
        avail{end + 1} = names{k}; %#ok<AGROW>
    end
end
if isempty(avail)
    error('netra:fuse:empty', 'No branch probabilities to fuse.');
end

useModel = nargin >= 2 && isstruct(models) && isfield(models, 'fusion') && ...
    ~isempty(models.fusion) && all(ismember(models.fusion.branches, avail));
if useModel
    x = netra.grading.stackFeatures(branches, models.fusion.branches);
    P = netra.grading.ordinalLogit('predict', models.fusion.model, x);
    method = 'ordinal-stacking';
else
    w = struct('cnn', 0.5, 'lesion', 0.3, 'rules', 0.2);
    wsum = 0;
    for k = 1:numel(avail)
        wsum = wsum + w.(avail{k});
    end
    logP = zeros(1, 5);
    for k = 1:numel(avail)
        pk = max(branches.(avail{k})(:)', 1e-4);
        logP = logP + (w.(avail{k}) / wsum) * log(pk / sum(pk));
    end
    P = exp(logP - max(logP));
    P = P / sum(P);
    method = 'log-opinion-pool';
end

Fz = struct();
Fz.P = P;
Fz.grade = find(cumsum(P) >= 0.5, 1) - 1;
Fz.expected = sum((0:4) .* P);
Fz.pReferable = sum(P(3:5));
Fz.pUrgent = P(5);
Fz.entropy = -sum(P .* log(max(P, 1e-12))) / log(5);
gr = zeros(1, numel(avail));
for k = 1:numel(avail)
    pk = branches.(avail{k});
    gr(k) = find(cumsum(pk) >= 0.5, 1) - 1;
end
Fz.branchGrades = gr;
Fz.branchNames = avail;
Fz.disagreement = max(gr) - min(gr);
Fz.branches = branches;
Fz.method = method;
end
