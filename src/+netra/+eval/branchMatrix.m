function [B, ok] = branchMatrix(recs, names)
%BRANCHMATRIX Branch probabilities of screened eyes as N x 5 matrices.
%   [B, ok] = netra.eval.branchMatrix(recs, {'cnn', 'lesion', 'rules'})
%   collects recs(i).cnnP / lesionP / rulesP (netra.eval.screenDataset)
%   into B.cnn, B.lesion, B.rules; ok marks eyes that were graded and have
%   every requested branch - the eyes a fusion model can be fitted or
%   evaluated on.
if nargin < 2
    names = {'cnn', 'lesion', 'rules'};
end
n = numel(recs);
ok = [recs.graded]';
B = struct();
for k = 1:numel(names)
    f = [names{k} 'P'];
    X = NaN(n, 5);
    for i = 1:n
        v = recs(i).(f);
        if numel(v) == 5
            X(i, :) = v(:)';
        end
    end
    B.(names{k}) = X;
    ok = ok & all(isfinite(X), 2);
end
end
