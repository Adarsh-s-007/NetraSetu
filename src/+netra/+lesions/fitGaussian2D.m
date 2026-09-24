function fit = fitGaussian2D(P, init, varargin)
%FITGAUSSIAN2D Sub-pixel Levenberg-Marquardt fit of an isotropic 2-D Gaussian.
%
%   fit = netra.lesions.fitGaussian2D(P, init) fits
%
%       f(x, y) = b0 + bx (x - xc) + by (y - yc)
%                 + a exp(-((x - x0)^2 + (y - y0)^2) / (2 s^2))
%
%   to the patch P (a microaneurysm in the darkening image 1 - gN, so the
%   blob is positive) on a tilted-plane background. Patch coordinates are
%   pixel centres 1..n; (xc, yc) is the patch centre.
%
%   init: [x0 y0 s a] starting values (patch coordinates).
%   Options: 'Weights' (same size as P, 0 excludes a pixel - e.g. a
%   neighbouring vessel), 'MaxIter' (30), 'MaxShift' (2.5 px), 'SigmaMax'.
%
%   fit fields
%     x0, y0     sub-pixel centre (patch coordinates)
%     s, a       width (px) and amplitude (darkening fraction)
%     b          [b0 bx by] background plane
%     r2         coefficient of determination over weighted pixels
%     resSigma   residual standard deviation
%     seXY       standard error of the centre (from (J'WJ)^-1 * resSigma^2)
%     crlb       Cramer-Rao bound sqrt(2/pi) * noise / a for the same noise
%     converged, iterations
%
%   With pixel noise sigma_n the CRLB for the centre of a Gaussian spot is
%   sigma_x >= sqrt(2/pi) * sigma_n / a, independent of s: a bright (dark)
%   enough microaneurysm is localised far below one pixel even when it is
%   only two pixels wide - which is what makes sub-pixel detection possible
%   on low-resolution smartphone captures.

o = netra.util.opts(struct('Weights', [], 'MaxIter', 30, 'MaxShift', 2.5, ...
    'SigmaMax', max(size(P)) / 2), varargin{:});
[n1, n2] = size(P);
[X, Y] = meshgrid(1:n2, 1:n1);
xc = (n2 + 1) / 2;
yc = (n1 + 1) / 2;
W = o.Weights;
if isempty(W)
    W = ones(n1, n2);
end
w = W(:);
x = X(:); y = Y(:); d = P(:);
keep = w > 0;
x = x(keep); y = y(keep); d = d(keep); w = w(keep);

% background initial guess from the patch border
border = [P(1, :), P(end, :), P(:, 1)', P(:, end)'];
b0 = median(border);
th = [init(1); init(2); max(init(3), 0.5); max(init(4), 1e-3); b0; 0; 0];
x0init = init(1:2);
lambda = 1e-2;
[r, J] = residual(th, x, y, d, xc, yc);
cost = sum(w .* r .^ 2);
converged = false;
it = 0;
for it = 1:o.MaxIter
    Jw = bsxfun(@times, J, w);
    A = J' * Jw;
    g = Jw' * r;
    step = -(A + lambda * diag(diag(A) + 1e-9)) \ g;
    cand = project(th + step, x0init, o.MaxShift, o.SigmaMax);
    [rc, Jc] = residual(cand, x, y, d, xc, yc);
    cc = sum(w .* rc .^ 2);
    if cc < cost
        rel = (cost - cc) / max(cost, eps);
        th = cand; r = rc; J = Jc; cost = cc;
        lambda = max(lambda / 3, 1e-7);
        if rel < 1e-7 || norm(step(1:3)) < 1e-4
            converged = true;
            break
        end
    else
        lambda = lambda * 4;
        if lambda > 1e7
            break
        end
    end
end

nEff = numel(d);
dof = max(nEff - 7, 1);
resSigma = sqrt(cost / sum(w) * nEff / dof);
dw = sum(w .* d) / sum(w);
ssTot = sum(w .* (d - dw) .^ 2);
Jw = bsxfun(@times, J, w);
A = J' * Jw;
cov = resSigma ^ 2 * pinv(A);
fit = struct();
fit.x0 = th(1);
fit.y0 = th(2);
fit.s = th(3);
fit.a = th(4);
fit.b = th(5:7)';
fit.r2 = 1 - cost / max(ssTot, eps);
fit.resSigma = resSigma;
fit.seXY = sqrt(max(cov(1, 1) + cov(2, 2), 0) / 2);
fit.crlb = sqrt(2 / pi) * resSigma / max(th(4), eps);
fit.converged = converged;
fit.iterations = it;

end

function [res, Jac] = residual(t, x, y, d, xc, yc)
dx = x - t(1);
dy = y - t(2);
s2 = t(3) ^ 2;
gss = exp(-(dx .^ 2 + dy .^ 2) / (2 * s2));
res = t(5) + t(6) * (x - xc) + t(7) * (y - yc) + t(4) * gss - d;
Jac = [t(4) * gss .* dx / s2, t(4) * gss .* dy / s2, ...
       t(4) * gss .* (dx .^ 2 + dy .^ 2) / (s2 * t(3)), gss, ...
       ones(size(x)), x - xc, y - yc];
end

function t = project(t, x0init, maxShift, sigmaMax)
sh = t(1:2) - x0init(:);
nrm = norm(sh);
if nrm > maxShift
    t(1:2) = x0init(:) + sh * maxShift / nrm;
end
t(3) = min(max(t(3), 0.4), sigmaMax);
t(4) = max(t(4), 1e-4);
end
