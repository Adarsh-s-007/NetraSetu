function ci = bootstrap(fun, n, varargin)
%BOOTSTRAP Percentile bootstrap confidence interval of a statistic.
%   ci = netra.eval.bootstrap(@(idx) statistic(idx), n) resamples the
%   indices 1..n with replacement 'B' times (default 2000) and returns the
%   'Alpha' (default 0.05) percentile interval plus the point estimate:
%   ci = [lo hi estimate]. Used for QWK and other non-binomial metrics.
o = netra.util.opts(struct('B', 2000, 'Alpha', 0.05, 'Seed', 7), varargin{:});
st = rng();
rng(o.Seed);
vals = zeros(o.B, 1);
for b = 1:o.B
    vals(b) = fun(randi(n, n, 1));
end
rng(st);
q = netra.util.pct(vals, 100 * [o.Alpha / 2, 1 - o.Alpha / 2]);
ci = [q(:)', fun((1:n)')];
end
