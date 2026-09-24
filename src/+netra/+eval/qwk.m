function k = qwk(y, yhat, K)
%QWK Quadratic weighted Cohen's kappa for ordinal grades 0..K-1.
%   The APTOS 2019 competition metric. Disagreeing by two grades costs four
%   times as much as disagreeing by one.
if nargin < 3
    K = max([y(:); yhat(:)]) + 1;
end
y = y(:) + 1;
yhat = yhat(:) + 1;
O = accumarray([y yhat], 1, [K K]);
n = sum(O(:));
E = sum(O, 2) * sum(O, 1) / max(n, 1);
[i, j] = ndgrid(1:K, 1:K);
W = (i - j) .^ 2 / (K - 1) ^ 2;
k = 1 - sum(W(:) .* O(:)) / max(sum(W(:) .* E(:)), eps);
end
