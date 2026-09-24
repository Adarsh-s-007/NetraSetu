function X = preprocess(S, cfg)
%PREPROCESS Network input for one eye: Graham-normalised canvas, 0..255 single.
%   X = netra.grading.cnn.preprocess(S, cfg) takes the standardised canvas
%   (netra.quality.standardize), subtracts the local average colour
%   (netra.quality.grahamPreprocess), blanks the rim and resizes to
%   cfg.grading.cnnInputSize. The 0..255 range matches the input
%   normalisation of ImageNet-pretrained backbones. Used verbatim for
%   training (via cacheDataset) and inference, so the two cannot drift.
X = netra.quality.grahamPreprocess(S.rgb, S.mask, S.radius, cfg.grading.cnnInputSize);
X = single(255 * X);
end
