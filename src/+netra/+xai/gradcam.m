function [cam, info] = gradcam(model, X, varargin)
%GRADCAM Where did the network look? Grad-CAM(++) for the DR grading CNN.
%
%   cam = netra.xai.gradcam(model, X)                    target: referable DR
%   cam = netra.xai.gradcam(model, X, 'Target', 4)       target: one grade
%   cam = netra.xai.gradcam(..., 'Method', 'gradcam')
%
%   The default target is the log-odds of referable DR,
%       s = logsumexp(z_2, z_3, z_4) - logsumexp(z_0, z_1),
%   computed from the logits (pre-softmax, so gradients do not vanish for
%   confident predictions). The map answers the clinical question "what
%   made this eye referable?" rather than "what made it grade 3 rather than
%   every other grade". Gradients are taken with dlfeval/dlgradient at the
%   layer feeding global average pooling (model.info.featureLayer).
%
%   cam is returned at the network input size in [0, 1]; info has the
%   target score and the raw low-resolution map.

o = netra.util.opts(struct('Target', 'referable', 'Method', 'gradcam++'), varargin{:});
if netra.util.isOctave()
    error('netra:gradcam:octave', 'Grad-CAM requires MATLAB with the Deep Learning Toolbox.');
end
dlX = dlarray(single(X), 'SSCB');
if canUseGPU
    dlX = gpuArray(dlX);
end
[A, G, s] = dlfeval(@camGradients, model.net, dlX, model.info.featureLayer, ...
    model.info.logitLayer, o.Target);
A = double(gather(A));
G = double(gather(G));
low = netra.xai.camFromGradients(A, G, o.Method);
S = size(X, 1);
cam = imresize(low, [S S], 'bilinear');
cam = max(cam, 0);
if max(cam(:)) > 0
    cam = cam / max(cam(:));
end
info = struct('score', double(gather(s)), 'lowRes', low, 'method', o.Method, ...
    'target', o.Target);
end

function [A, G, s] = camGradients(net, dlX, featureLayer, logitLayer, target)
[act, z] = forward(net, dlX, 'Outputs', {featureLayer, logitLayer});
z = z(:, 1);
if ischar(target) && strcmpi(target, 'referable')
    s = lse(z(3:5)) - lse(z(1:2));
else
    s = z(target + 1);
end
g = dlgradient(s, act);
A = extractdata(act);
G = extractdata(g);
s = extractdata(s);
end

function v = lse(z)
m = max(z);
v = m + log(sum(exp(z - m)));
end
