function J = smooth(I, sigma)
%SMOOTH Gaussian smoothing that stays fast for very large sigma.
%   J = netra.util.smooth(I, sigma) equals imgaussfilt(I, sigma) for
%   sigma <= 6 px. Larger kernels (illumination and background estimates)
%   are applied on a reduced grid and interpolated back, which is accurate
%   because the result contains no detail finer than sigma. Behaviour is
%   identical in MATLAB and Octave.
if sigma <= 6
    J = imgaussfilt(I, sigma);
    return
end
f = floor(sigma / 3);
[h, w, c] = size(I);
hs = max(4, ceil(h / f));
ws = max(4, ceil(w / f));
J = zeros(h, w, c);
for k = 1:c
    small = imresize(imgaussfilt(I(:, :, k), 0.5 * f), [hs ws], 'bilinear');
    small = imgaussfilt(small, sqrt(max(sigma ^ 2 - (0.5 * f) ^ 2, 1)) * hs / h);
    J(:, :, k) = imresize(small, [h w], 'bilinear');
end
end
