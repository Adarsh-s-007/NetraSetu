function out = ordinalLogit(action, varargin)
%ORDINALLOGIT Proportional-odds (cumulative logit) model for ordinal grades.
%
%   model = netra.grading.ordinalLogit('fit', X, y)
%   model = netra.grading.ordinalLogit('fit', X, y, 'Lambda', 1e-2, 'Weights', w)
%   P     = netra.grading.ordinalLogit('predict', model, X)
%
%       P(y <= k | x) = sigmoid(theta_k - x * beta),   k = 0 .. K-2
%
%   One slope vector shared by all thresholds: a feature that makes a grade
%   more likely pushes the whole distribution upwards. For DR severity this
%   is both the right structure (the grades are ordered stages of one
%   disease) and a strong regulariser: 13 fused inputs cost 13 + 4
%   parameters instead of 13 x 4 for a multinomial model.
%
%   Fitting minimises the (weighted) negative log-likelihood plus
%   Lambda/2 * ||beta||^2 with BFGS; thresholds are parameterised as
%   theta_1 = a_1, theta_k = theta_(k-1) + exp(a_k) so they stay ordered.
%   Inputs are standardised internally. y holds grades 0 .. K-1.

switch lower(action)
    case 'fit'
        out = fitModel(varargin{:});
    case 'predict'
        out = predictModel(varargin{:});
    otherwise
        error('netra:ordinalLogit:action', 'Unknown action "%s".', action);
end
end

function model = fitModel(X, y, varargin)
o = netra.util.opts(struct('Lambda', 1e-2, 'Weights', [], 'K', max(y) + 1), varargin{:});
[n, p] = size(X);
K = o.K;
w = o.Weights;
if isempty(w)
    w = ones(n, 1);
end
w = w(:) / mean(w);
mu = mean(X, 1);
sd = std(X, 0, 1);
sd(sd < 1e-9) = 1;
Z = (X - mu) ./ sd;
% initial thresholds from cumulative class frequencies
cum = cumsum(accumarray(y(:) + 1, 1, [K 1])) / n;
cum = min(max(cum(1:K - 1), 0.02), 0.98);
th0 = log(cum ./ (1 - cum));
th0 = sort(th0);
a0 = [th0(1); log(max(diff(th0), 0.05))];
x0 = [a0; zeros(p, 1)];
f = @(v) nll(v, Z, y(:) + 1, w, K, o.Lambda);
[v, fval, info] = netra.util.bfgs(f, x0, 'MaxIter', 500);
model = struct('type', 'ordinalLogit', 'K', K, 'theta', thetaFrom(v(1:K - 1)), ...
    'beta', v(K:end), 'mu', mu, 'sd', sd, 'lambda', o.Lambda, 'nll', fval, ...
    'converged', info.converged);
end

function P = predictModel(model, X)
Z = (X - model.mu) ./ model.sd;
eta = Z * model.beta;
cumP = netra.util.sigmoid(model.theta(:)' - eta);        % n x (K-1)
P = diff([zeros(size(eta)), cumP, ones(size(eta))], 1, 2);
P = max(P, 0);
P = P ./ sum(P, 2);
end

function th = thetaFrom(a)
th = cumsum([a(1); exp(a(2:end))]);
end

function [f, g] = nll(v, Z, c, w, K, lambda)
% c: class index 1..K
n = size(Z, 1);
a = v(1:K - 1);
beta = v(K:end);
th = thetaFrom(a);
eta = Z * beta;
thExt = [-Inf; th; Inf];
up = thExt(c + 1) - eta;
lo = thExt(c) - eta;
Fu = netra.util.sigmoid(up);
Fl = netra.util.sigmoid(lo);
Fu(c == K) = 1;
Fl(c == 1) = 0;
Pi = max(Fu - Fl, 1e-12);
f = -sum(w .* log(Pi)) / n + 0.5 * lambda * sum(beta .^ 2);
fu = Fu .* (1 - Fu);
fl = Fl .* (1 - Fl);
fu(c == K) = 0;
fl(c == 1) = 0;
% d/d theta_j
gth = zeros(K - 1, 1);
for j = 1:K - 1
    gth(j) = -sum(w(c == j) .* fu(c == j) ./ Pi(c == j)) + ...
              sum(w(c == j + 1) .* fl(c == j + 1) ./ Pi(c == j + 1));
end
gth = gth / n;
% d/d a via theta = cumsum([a1, exp(a2..)])
ga = zeros(K - 1, 1);
ga(1) = sum(gth);
for k = 2:K - 1
    ga(k) = exp(a(k)) * sum(gth(k:end));
end
geta = w .* (fu - fl) ./ Pi / n;
gb = Z' * geta + lambda * beta;
g = [ga; gb];
end
