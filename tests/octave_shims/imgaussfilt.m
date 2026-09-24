function B = imgaussfilt(A, sigma, varargin)
%IMGAUSSFILT Octave shim for the Image Processing Toolbox function.
%   Separable Gaussian filtering with replicated borders, kernel length
%   2*ceil(2*sigma)+1 (MATLAB's default FilterSize). Only loaded under
%   GNU Octave; MATLAB always uses its own implementation.
if nargin < 2 || isempty(sigma)
    sigma = 0.5;
end
if isscalar(sigma)
    sigma = [sigma sigma];
end
cls = class(A);
A = double(A);
B = A;
kr = kernel(sigma(1));
kc = kernel(sigma(2));
pr = (numel(kr) - 1) / 2;
pc = (numel(kc) - 1) / 2;
for k = 1:size(A, 3)
    P = padarray(A(:, :, k), [pr pc], 'replicate');
    P = conv2(kr(:), kc(:)', P, 'valid');
    B(:, :, k) = P;
end
if ~strcmp(cls, 'double')
    B = cast(B, cls);
end
end

function k = kernel(s)
if s <= 0
    k = 1;
    return
end
h = ceil(2 * s);
x = -h:h;
k = exp(-x .^ 2 / (2 * s ^ 2));
k = k / sum(k);
end
