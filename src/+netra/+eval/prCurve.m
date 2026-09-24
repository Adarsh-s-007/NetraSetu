function pr = prCurve(label, score)
%PRCURVE Precision-recall curve and its area (step-wise, as in IDRiD).
label = logical(label(:));
[s, order] = sort(score(:), 'descend');
l = label(order);
P = nnz(l);
last = [s(1:end - 1) ~= s(2:end); true];
tp = cumsum(l);
k = (1:numel(l))';
prec = tp(last) ./ k(last);
rec = tp(last) / max(P, 1);
pr = struct('precision', [1; prec], 'recall', [0; rec]);
pr.aupr = sum(diff(pr.recall) .* pr.precision(2:end));
end
