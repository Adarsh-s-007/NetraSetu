function J = imscale(I, s, method)
%IMSCALE Anti-aliased image resize with identical behaviour in MATLAB and Octave.
%   J = netra.util.imscale(I, scale)
%   J = netra.util.imscale(I, [rows cols])
%   J = netra.util.imscale(..., method)   'bilinear' (default) | 'nearest' | 'bicubic'
%
%   Shrinking applies a Gaussian pre-filter (sigma = 0.45 / scale) so that
%   noise and fine vessels do not alias; MATLAB's built-in antialiasing is
%   switched off to avoid filtering twice.
if nargin < 3
    method = 'bilinear';
end
[h, w, c] = size(I);
if isscalar(s)
    target = max(1, round([h w] * s));
else
    target = round(s(1:2));
end
f = min(target ./ [h w]);
if f < 0.999 && ~strcmp(method, 'nearest') && ~islogical(I)
    sigma = 0.45 / f;
    for k = 1:c
        I(:, :, k) = imgaussfilt(I(:, :, k), sigma);
    end
end
if netra.util.isOctave()
    J = imresize(I, target, method);
else
    J = imresize(I, target, method, 'Antialiasing', false);
end
end
