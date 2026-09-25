function P = fusedP(B, F, names)
%FUSEDP Fused grade distribution for many eyes at once (N x 5).
%   P = netra.eval.fusedP(B, F) with B from netra.eval.branchMatrix and F a
%   fusion model (netra.grading.trainFusion) - the batch equivalent of
%   netra.grading.fuse. With F = [] the logarithmic opinion pool over the
%   branches in NAMES (default: fields of B) is used, with fuse's weights.
if nargin >= 2 && ~isempty(F)
    X = netra.grading.stackFeatures(B, F.branches);
    P = netra.grading.ordinalLogit('predict', F.model, X);
    return
end
if nargin < 3
    names = fieldnames(B)';
end
w = struct('cnn', 0.5, 'lesion', 0.3, 'rules', 0.2);
wsum = 0;
for k = 1:numel(names)
    wsum = wsum + w.(names{k});
end
logP = 0;
for k = 1:numel(names)
    pk = max(B.(names{k}), 1e-4);
    pk = pk ./ repmat(sum(pk, 2), 1, 5);
    logP = logP + (w.(names{k}) / wsum) * log(pk);
end
P = exp(logP - repmat(max(logP, [], 2), 1, 5));
P = P ./ repmat(sum(P, 2), 1, 5);
end
