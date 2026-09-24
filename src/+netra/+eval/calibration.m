function c = calibration(p, y, nBins)
%CALIBRATION Reliability of predicted probabilities for a binary outcome.
%   c = netra.eval.calibration(p, y) - expected and maximum calibration
%   error (equal-width bins, default 10), Brier score and the reliability
%   curve (bin confidence vs observed frequency, with counts).
if nargin < 3
    nBins = 10;
end
p = p(:);
y = double(y(:));
edges = linspace(0, 1, nBins + 1);
b = min(max(floor(p * nBins) + 1, 1), nBins);
conf = accumarray(b, p, [nBins 1]) ./ max(accumarray(b, 1, [nBins 1]), 1);
freq = accumarray(b, y, [nBins 1]) ./ max(accumarray(b, 1, [nBins 1]), 1);
cnt = accumarray(b, 1, [nBins 1]);
gap = abs(conf - freq);
c = struct();
c.ece = sum(cnt .* gap) / max(numel(p), 1);
c.mce = max(gap(cnt > 0));
if isempty(c.mce), c.mce = 0; end
c.brier = mean((p - y) .^ 2);
c.binConfidence = conf;
c.binFrequency = freq;
c.binCount = cnt;
c.edges = edges;
end
