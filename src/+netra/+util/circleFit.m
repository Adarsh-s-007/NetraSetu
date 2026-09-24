function [c, r, inl] = circleFit(x, y, nIter)
%CIRCLEFIT Robust algebraic (Kasa) circle fit.
%   [centre, radius, inliers] = netra.util.circleFit(x, y) fits a circle to
%   boundary points, iteratively discarding points whose radial residual is
%   larger than 3 robust sigmas (camera notches, eyelids, clipped borders).
if nargin < 3
    nIter = 4;
end
x = x(:);
y = y(:);
inl = true(size(x));
c = [NaN NaN];
r = NaN;
for it = 1:nIter
    if nnz(inl) < 3
        break
    end
    A = [x(inl), y(inl), ones(nnz(inl), 1)];
    b = -(x(inl) .^ 2 + y(inl) .^ 2);
    p = A \ b;
    c = [-p(1) / 2, -p(2) / 2];
    r = sqrt(max(c(1) ^ 2 + c(2) ^ 2 - p(3), 0));
    res = abs(hypot(x - c(1), y - c(2)) - r);
    [~, s] = netra.util.robustStats(res(inl));
    newInl = res <= max(3 * s, 1.0);
    if isequal(newInl, inl)
        break
    end
    inl = newInl;
end
end
