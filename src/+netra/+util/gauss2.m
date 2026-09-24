function J = gauss2(I, sy, sx)
%GAUSS2 Anisotropic separable Gaussian smoothing (sy along rows, sx along columns).
%   Explicit kernels avoid any ambiguity in the argument order of toolbox
%   functions; borders are replicated.
ky = kern(sy);
kx = kern(sx);
py = (numel(ky) - 1) / 2;
px = (numel(kx) - 1) / 2;
J = zeros(size(I));
for c = 1:size(I, 3)
    P = padarray(I(:, :, c), [py px], 'replicate');
    J(:, :, c) = conv2(ky(:), kx(:)', P, 'valid');
end
end

function k = kern(s)
if s <= 0
    k = 1;
    return
end
h = ceil(3 * s);
x = -h:h;
k = exp(-x .^ 2 / (2 * s ^ 2));
k = k / sum(k);
end
