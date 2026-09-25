function pre = prepareImage(img, cfg)
%PREPAREIMAGE Field of view, quality, standard canvas and enhancement of one photograph.
%   pre = netra.eval.prepareImage(fileOrRGB, cfg) returns rgb, F (aperture),
%   Q (quality), S (canvas, netra.quality.standardize) and E (analysis
%   channels, netra.quality.enhance): the common first half of the
%   pipeline, for experiments that score a single stage (vessels, lesions,
%   localisation) at the benchmark's native resolution.
if ischar(img)
    img = netra.io.readFundus(img);
end
rgb = netra.util.toRGB(img);
F = netra.quality.fovMask(rgb);
Q = netra.quality.assess(rgb, cfg, F);
S = netra.quality.standardize(rgb, F, cfg.scale.workDiameter);
E = netra.quality.enhance(S, cfg, Q);
pre = struct('rgb', rgb, 'F', F, 'Q', Q, 'S', S, 'E', E);
end
