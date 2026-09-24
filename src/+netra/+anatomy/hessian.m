function H = hessian(I, sigma)
%HESSIAN Scale-normalised Hessian eigen-analysis of an image.
%
%   H = netra.anatomy.hessian(I, sigma) returns, at scale sigma (px),
%     l1, l2   eigenvalues ordered by magnitude, |l1| <= |l2|, scale-
%              normalised by sigma^2
%     theta    orientation of the eigenvector belonging to the algebraically
%              larger eigenvalue; for BRIGHT line structures (vessels in
%              1 - green) this is the direction ALONG the vessel
%              (radians, x to the right, y down, defined modulo pi)
%     Hxx, Hxy, Hyy
%   using separable Gaussian-derivative kernels with replicated borders.
%
%   Bright tubes: l2 << 0, |l1| ~ 0.  Bright blobs: l1 ~ l2 << 0.

h = ceil(3 * sigma);
x = -h:h;
g = exp(-x .^ 2 / (2 * sigma ^ 2));
g = g / sum(g);
g1 = -x / sigma ^ 2 .* g;
g2 = (x .^ 2 / sigma ^ 4 - 1 / sigma ^ 2) .* g;
P = padarray(I, [h h], 'replicate');
% conv2(u, v, A) filters columns with u (along y) and rows with v (along x)
s2 = sigma ^ 2;
Hxx = s2 * conv2(g(:), g2(:)', P, 'valid');
Hyy = s2 * conv2(g2(:), g(:)', P, 'valid');
Hxy = s2 * conv2(g1(:), g1(:)', P, 'valid');
tmp = sqrt((Hxx - Hyy) .^ 2 + 4 * Hxy .^ 2);
mu1 = 0.5 * (Hxx + Hyy + tmp);        % algebraically larger
mu2 = 0.5 * (Hxx + Hyy - tmp);
swap = abs(mu1) > abs(mu2);
l1 = mu1;
l2 = mu2;
l1(swap) = mu2(swap);
l2(swap) = mu1(swap);
theta = 0.5 * atan2(2 * Hxy, Hxx - Hyy);
H = struct('l1', l1, 'l2', l2, 'theta', theta, 'Hxx', Hxx, 'Hxy', Hxy, 'Hyy', Hyy);
end
