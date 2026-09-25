function P = vesselVariants(resp, contrast, fov, cfg, beta)
%VESSELVARIANTS Vessel probability of each single detector and of their fusions.
%   P = netra.eval.vesselVariants(V.response, V.contrast, V.fovMask, cfg, beta)
%   rebuilds, from ONE run of netra.anatomy.vessels, the map each variant
%   of the detector ablation would produce (vessel resolution, [0, 1], zero
%   outside the FOV) - the same arithmetic as the 'Detectors' option and
%   the learned fusion inside netra.anatomy.vessels:
%     hessian, line, tophat   one normalised detector
%     average                 cfg.vessels.weights-weighted mean of the three
%     fusion                  logistic model on [hessian line tophat contrast]
%                             (only when beta is given)
names = {'hessian', 'line', 'tophat'};
P = struct();
acc = zeros(size(resp.hessian));
wsum = 0;
for k = 1:numel(names)
    r = double(resp.(names{k}));
    P.(names{k}) = clip(r, fov);
    w = cfg.vessels.weights.(names{k});
    acc = acc + w * r;
    wsum = wsum + w;
end
P.average = clip(acc / wsum, fov);
if nargin >= 5 && ~isempty(beta)
    X = [double(resp.hessian(:)), double(resp.line(:)), double(resp.tophat(:)), double(contrast(:))];
    P.fusion = clip(reshape(netra.util.logistic('predict', beta, X), size(acc)), fov);
end
end

function x = clip(x, fov)
x(~fov) = 0;
x = min(max(x, 0), 1);
end
