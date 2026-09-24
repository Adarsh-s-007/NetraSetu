function t = otsu(v, nbins)
%OTSU Otsu threshold of a vector of values in [0, 1] (toolbox-free).
%   t = netra.util.otsu(v) maximises the between-class variance of a
%   256-bin histogram. Works on any array shape (Octave's GRAYTHRESH does not).
if nargin < 2
    nbins = 256;
end
v = v(isfinite(v(:)));
if isempty(v)
    t = 0.5;
    return
end
v = min(max(v, 0), 1);
idx = min(floor(v * nbins) + 1, nbins);
p = accumarray(idx, 1, [nbins 1]) / numel(v);
omega = cumsum(p);
mu = cumsum(p .* (1:nbins)');
muT = mu(end);
sigmaB = (muT * omega - mu) .^ 2 ./ max(omega .* (1 - omega), eps);
[~, k] = max(sigmaB);
t = (k - 0.5) / nbins;
end
