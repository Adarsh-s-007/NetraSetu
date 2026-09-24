function X = grahamPreprocess(rgb, mask, radius, outSize)
%GRAHAMPREPROCESS Local-colour subtraction used for the CNN input.
%
%   X = netra.quality.grahamPreprocess(rgb, mask, radius, outSize) applies
%   the preprocessing of Ben Graham's winning entry to the 2015 Kaggle
%   Diabetic Retinopathy challenge,
%       X = 4 * (I - G_sigma * I) + 0.5,   sigma = radius / 30,
%   which removes illumination and pigmentation differences while keeping
%   lesion-scale detail, then blanks everything outside 95 % of the FOV
%   radius to neutral grey and resizes to outSize x outSize.
%   Training and inference both call this function, so they cannot drift.
if nargin < 4
    outSize = size(rgb, 1);
end
F = netra.util.fillOutside(rgb, mask, 2);
sigma = radius / 30;
X = zeros(size(F));
for k = 1:3
    X(:, :, k) = 4 * (F(:, :, k) - imgaussfilt(F(:, :, k), sigma)) + 0.5;
end
X = min(max(X, 0), 1);
[h, w, ~] = size(X);
[Xc, Yc] = meshgrid(1:w, 1:h);
inside = hypot(Xc - (w + 1) / 2, Yc - (h + 1) / 2) <= 0.95 * radius;
for k = 1:3
    ch = X(:, :, k);
    ch(~inside) = 0.5;
    X(:, :, k) = ch;
end
if outSize ~= h
    X = netra.util.imscale(X, [outSize outSize]);
end
end
