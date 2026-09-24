function [T, nllBefore, nllAfter] = temperatureScale(logits, y)
%TEMPERATURESCALE Fit the temperature that calibrates a network's softmax.
%   T = netra.grading.temperatureScale(logits, y) minimises the negative
%   log-likelihood of softmax(logits / T) on held-out data (Guo et al., ICML
%   2017). logits is N x K, y holds classes 0..K-1. One scalar leaves the
%   ranking (and therefore AUC and accuracy) untouched and removes the
%   over-confidence typical of fine-tuned CNNs.
y = y(:) + 1;
n = numel(y);
idx = sub2ind(size(logits), (1:n)', y);
f = @(lt) nllAt(logits, idx, exp(lt));
lt = fminbnd(f, log(0.05), log(20));
T = exp(lt);
nllBefore = nllAt(logits, idx, 1);
nllAfter = nllAt(logits, idx, T);
end

function v = nllAt(logits, idx, T)
P = netra.util.softmax(logits / T, 2);
v = -mean(log(max(P(idx), 1e-12)));
end
