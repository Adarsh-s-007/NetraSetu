function ci = wilson(k, n, alpha)
%WILSON Wilson score interval for a binomial proportion k / n.
%   ci = netra.eval.wilson(k, n) returns the 95 % interval [lo hi]. Unlike
%   the Wald interval it behaves at proportions near 0 or 1 - exactly where
%   sensitivities and specificities of screening tests live.
if nargin < 3
    alpha = 0.05;
end
if n == 0
    ci = [0 1];
    return
end
z = netra.util.phiinv(1 - alpha / 2);
p = k / n;
den = 1 + z ^ 2 / n;
c = (p + z ^ 2 / (2 * n)) / den;
h = z * sqrt(p * (1 - p) / n + z ^ 2 / (4 * n ^ 2)) / den;
ci = [max(0, c - h), min(1, c + h)];
end
