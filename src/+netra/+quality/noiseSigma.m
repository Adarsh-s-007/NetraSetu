function sigma = noiseSigma(I, mask)
%NOISESIGMA Robust estimate of additive noise (Immerkaer, CVIU 1996).
%   sigma = netra.quality.noiseSigma(I, mask) filters I with the Laplacian
%   difference kernel [1 -2 1; -2 4 -2; 1 -2 1], which cancels any locally
%   planar signal, and converts the median absolute response inside MASK to
%   a Gaussian sigma. The median (instead of Immerkaer's mean) keeps vessel
%   edges from being counted as noise.
k = [1 -2 1; -2 4 -2; 1 -2 1];
r = conv2(I, k, 'same');
if nargin < 2
    mask = true(size(I));
end
mask = imerode(mask, true(5));
v = abs(r(mask));
if isempty(v)
    sigma = NaN;
    return
end
sigma = median(v) / (0.6745 * 6);
end
