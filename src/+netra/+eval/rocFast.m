function r = rocFast(label, score)
%ROCFAST ROC AUC for very large samples (pixels), without DeLong variance.
label = logical(label(:));
[s, order] = sort(score(:), 'descend');
l = label(order);
P = nnz(l);
N = numel(l) - P;
last = [s(1:end - 1) ~= s(2:end); true];
tp = cumsum(l);
fp = cumsum(~l);
r.tpr = [0; tp(last) / max(P, 1)];
r.fpr = [0; fp(last) / max(N, 1)];
r.auc = trapz(r.fpr, r.tpr);
end
