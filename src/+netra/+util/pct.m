function q = pct(x, p)
%PCT Percentiles with linear interpolation (toolbox-free PRCTILE).
%   q = netra.util.pct(x, p) returns the p-th percentiles (0..100) of the
%   finite values in x, using the same definition as MATLAB's PRCTILE.
x = sort(x(isfinite(x(:))));
n = numel(x);
q = nan(size(p));
if n == 0
    return
end
if n == 1
    q(:) = x;
    return
end
% prctile convention: x(i) is the (100*(i-0.5)/n)-th percentile
pos = n * p(:) / 100 + 0.5;
pos = min(max(pos, 1), n);
lo = floor(pos);
hi = min(lo + 1, n);
w = pos - lo;
q(:) = (1 - w) .* x(lo) + w .* x(hi);
end
