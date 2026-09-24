function cam = camFromGradients(A, G, method)
%CAMFROMGRADIENTS Class activation map from feature maps and their gradients.
%
%   cam = netra.xai.camFromGradients(A, G, method)
%     A, G    h x w x K activations of the last convolutional block and the
%             gradients of the target score with respect to them
%     method  'gradcam'   (Selvaraju et al., ICCV 2017):
%                 w_k = mean_ij G_kij,  cam = ReLU(sum_k w_k A_k)
%             'gradcam++' (Chattopadhay et al., WACV 2018, default):
%                 alpha_kij = G^2 / (2 G^2 + sum_ab A_kab G^3),
%                 w_k = sum_ij alpha_kij ReLU(G_kij)
%   Grad-CAM++ spreads credit over several objects of the same class, which
%   matters in DR where the evidence is many small lesions rather than one
%   object. The map is returned in [0, 1] (all zeros if nothing is positive).
if nargin < 3
    method = 'gradcam++';
end
[h, w, K] = size(A);
Af = reshape(A, h * w, K);
Gf = reshape(G, h * w, K);
switch lower(method)
    case 'gradcam'
        wk = mean(Gf, 1);
    case 'gradcam++'
        g2 = Gf .^ 2;
        g3 = Gf .^ 3;
        denom = 2 * g2 + sum(Af, 1) .* g3;
        denom(abs(denom) < eps) = eps;
        alpha = g2 ./ denom;
        wk = sum(alpha .* max(Gf, 0), 1);
    otherwise
        error('netra:cam:method', 'Unknown CAM method "%s".', method);
end
cam = reshape(max(Af * wk(:), 0), h, w);
mx = max(cam(:));
if mx > 0
    cam = cam / mx;
end
end
