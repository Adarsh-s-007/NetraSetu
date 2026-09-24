function r = roc(label, score)
%ROC Receiver operating characteristic curve and its area.
%   r = netra.eval.roc(label, score) with logical labels. Ties in score are
%   handled exactly (one ROC point per distinct threshold), so the AUC
%   equals the Mann-Whitney statistic P(score+ > score-) + 0.5 P(tie).
%   Fields: fpr, tpr, thresholds, auc, aucCI (DeLong), nPos, nNeg.
label = logical(label(:));
score = score(:);
[s, order] = sort(score, 'descend');
l = label(order);
P = nnz(l);
N = numel(l) - P;
last = [s(1:end - 1) ~= s(2:end); true];
tp = cumsum(l);
fp = cumsum(~l);
r = struct();
r.tpr = [0; tp(last) / max(P, 1)];
r.fpr = [0; fp(last) / max(N, 1)];
r.thresholds = [Inf; s(last)];
r.auc = trapz(r.fpr, r.tpr);
r.nPos = P;
r.nNeg = N;
d = netra.eval.delong(label, score);
r.aucCI = d.ci(1, :);
r.aucSE = d.se(1);
end
