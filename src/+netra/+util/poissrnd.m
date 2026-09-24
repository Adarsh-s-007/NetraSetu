function k = poissrnd(lambda)
%POISSRND Poisson random numbers (toolbox-free, vectorised).
%   Knuth's multiplication method for lambda < 30, rounded normal
%   approximation (with continuity correction) above.
k = zeros(size(lambda));
small = lambda > 0 & lambda < 30;
if any(small(:))
    L = exp(-lambda(small));
    p = ones(size(L));
    c = zeros(size(L));
    active = true(size(L));
    while any(active)
        p(active) = p(active) .* rand(nnz(active), 1);
        stillAbove = p > L;
        c(active & stillAbove) = c(active & stillAbove) + 1;
        active = active & stillAbove;
    end
    k(small) = c;
end
big = lambda >= 30;
if any(big(:))
    lb = lambda(big);
    k(big) = max(0, round(lb + sqrt(lb) .* randn(size(lb))));
end
end
