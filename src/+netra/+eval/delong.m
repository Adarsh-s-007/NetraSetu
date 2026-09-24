function d = delong(label, varargin)
%DELONG DeLong's nonparametric AUC variance and paired comparison.
%
%   d = netra.eval.delong(label, s1)          AUC, SE and 95 % CI
%   d = netra.eval.delong(label, s1, s2, ...) plus the covariance matrix and
%                                            the two-sided p-value of
%                                            AUC(s1) = AUC(s2) for correlated
%                                            ROC curves on the same eyes
%
%   DeLong, DeLong & Clarke-Pearson, Biometrics 1988. This is the test used
%   to show that the integrated pipeline beats each single technique on the
%   same validation images (experiments/exp04_validate_grading.m).
label = logical(label(:));
S = cell2mat(cellfun(@(v) v(:), varargin, 'UniformOutput', false));
m = nnz(label);
n = nnz(~label);
k = size(S, 2);
X = S(label, :);
Y = S(~label, :);
V10 = zeros(m, k);
V01 = zeros(n, k);
auc = zeros(1, k);
for j = 1:k
    % psi(x, y) = 1 if x > y, 0.5 if tie
    xs = X(:, j);
    ys = Y(:, j);
    Ymat = ys';
    psi = double(xs > Ymat) + 0.5 * double(xs == Ymat);
    V10(:, j) = mean(psi, 2);
    V01(:, j) = mean(psi, 1)';
    auc(j) = mean(V10(:, j));
end
S10 = cov(V10);
S01 = cov(V01);
if k == 1
    S10 = var(V10);
    S01 = var(V01);
end
C = S10 / max(m, 1) + S01 / max(n, 1);
se = sqrt(max(diag(C), 0))';
z = netra.util.phiinv(0.975);
d = struct('auc', auc, 'se', se, 'cov', C);
d.ci = [auc' - z * se', auc' + z * se'];
d.ci = min(max(d.ci, 0), 1);
if k >= 2
    d.p = nan(k);
    for a = 1:k
        for b = a + 1:k
            v = C(a, a) + C(b, b) - 2 * C(a, b);
            zz = (auc(a) - auc(b)) / sqrt(max(v, eps));
            d.p(a, b) = 2 * (1 - netra.util.phi(abs(zz)));
            d.p(b, a) = d.p(a, b);
        end
    end
end
end
