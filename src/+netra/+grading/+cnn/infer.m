function out = infer(model, X, cfg)
%INFER Calibrated CNN grade probabilities with test-time augmentation.
%
%   out = netra.grading.cnn.infer(model, X, cfg) with X from
%   netra.grading.cnn.preprocess. Logits of cfg.grading.tta views
%   (identity, horizontal flip, vertical flip, 180 deg rotation) are
%   averaged, divided by the fitted temperature and passed through softmax.
%
%   out fields: P (1 x 5), logits (1 x 5, averaged), viewP (views x 5),
%   spread (standard deviation of P(referable) across views - an epistemic
%   warning light), temperature.

nViews = max(1, min(4, cfg.grading.tta));
views = {@(x) x, @(x) fliplr(x), @(x) flipud(x), @(x) rot90(x, 2)};
S = model.info.inputSize;
batch = zeros(S, S, 3, nViews, 'single');
for v = 1:nViews
    batch(:, :, :, v) = views{v}(single(X));
end
dlX = dlarray(batch, 'SSCB');
if canUseGPU
    dlX = gpuArray(dlX);
end
z = predict(model.net, dlX, 'Outputs', model.info.logitLayer);
Z = double(gather(extractdata(z)))';                    % views x 5
T = model.temperature;
Pv = netra.util.softmax(Z / T, 2);
zbar = mean(Z, 1);
out = struct();
out.logits = zbar;
out.P = netra.util.softmax(zbar / T, 2);
out.viewP = Pv;
out.spread = std(sum(Pv(:, 3:5), 2));
out.temperature = T;
end
