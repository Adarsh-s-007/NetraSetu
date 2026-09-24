function t = mcnemar(correctA, correctB)
%MCNEMAR Exact McNemar test for two paired binary classifiers.
%   t = netra.eval.mcnemar(correctA, correctB) compares, on the same eyes,
%   which method is right more often (e.g. sensitivity of the integrated
%   pipeline vs the CNN alone on the referable eyes). Exact two-sided
%   binomial p-value on the discordant pairs.
a = logical(correctA(:));
b = logical(correctB(:));
n01 = nnz(a & ~b);
n10 = nnz(~a & b);
n = n01 + n10;
k = min(n01, n10);
if n == 0
    p = 1;
else
    % P(X <= k) for X ~ Bin(n, 0.5) via the regularised incomplete beta
    cdf = betainc(0.5, n - k, k + 1);
    p = min(1, 2 * cdf);
end
t = struct('aBetter', n01, 'bBetter', n10, 'p', p);
end
