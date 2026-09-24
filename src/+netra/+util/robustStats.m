function [med, sigma] = robustStats(x)
%ROBUSTSTATS Median and MAD-based standard deviation of the finite values of X.
%   sigma = 1.4826 * median(|x - median(x)|) is a consistent estimator of the
%   standard deviation for Gaussian data and ignores up to half the samples
%   being lesions, vessels or artefacts.
x = x(isfinite(x));
if isempty(x)
    med = NaN;
    sigma = NaN;
    return
end
med = median(x);
sigma = 1.4826 * median(abs(x - med));
if sigma <= 0
    sigma = std(x);
end
if sigma <= 0
    sigma = eps;
end
end
