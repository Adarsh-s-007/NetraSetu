function [x, f, info] = bfgs(fun, x0, varargin)
%BFGS Unconstrained quasi-Newton minimiser (toolbox-free FMINUNC).
%   [x, f] = netra.util.bfgs(fun, x0) minimises FUN, which must return the
%   objective and its gradient: [f, g] = fun(x). Options (name-value):
%     MaxIter (200), TolGrad (1e-6), TolFun (1e-10)
o = netra.util.opts(struct('MaxIter', 200, 'TolGrad', 1e-6, 'TolFun', 1e-10), varargin{:});
x = x0(:);
n = numel(x);
[f, g] = fun(x);
g = g(:);
Hinv = eye(n);
info = struct('iterations', 0, 'converged', false);
for it = 1:o.MaxIter
    if norm(g, Inf) < o.TolGrad
        info.converged = true;
        break
    end
    d = -Hinv * g;
    if g' * d >= 0              % not a descent direction: reset curvature
        Hinv = eye(n);
        d = -g;
    end
    t = 1;
    accepted = false;
    for ls = 1:40               % Armijo backtracking
        xn = x + t * d;
        [fn, gn] = fun(xn);
        if isfinite(fn) && fn <= f + 1e-4 * t * (g' * d)
            accepted = true;
            break
        end
        t = t / 2;
    end
    if ~accepted
        break
    end
    gn = gn(:);
    s = xn - x;
    y = gn - g;
    sy = s' * y;
    if sy > 1e-12
        rho = 1 / sy;
        V = eye(n) - rho * (s * y');
        Hinv = V * Hinv * V' + rho * (s * s');
    end
    df = f - fn;
    x = xn;
    f = fn;
    g = gn;
    info.iterations = it;
    if abs(df) < o.TolFun * max(1, abs(f))
        info.converged = true;
        break
    end
end
x = reshape(x, size(x0));
end
