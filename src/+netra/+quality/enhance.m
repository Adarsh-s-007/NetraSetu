function E = enhance(S, cfg, Q)
%ENHANCE Noise-adaptive illumination, colour and contrast normalisation.
%
%   E = netra.quality.enhance(S, cfg, Q) takes the standardised canvas S
%   (netra.quality.standardize) and returns the analysis channels used by
%   every downstream detector together with a display image:
%
%     gN       illumination-normalised green channel: background = 1, so a
%              value of 0.8 means "20 % darker than the local retina"; all
%              lesion thresholds are expressed in these contrast units
%     rgbN     each channel divided by its own background and re-coloured to
%              cfg.enhance.targetRGB: removes vignetting, flash tilt and much
%              of the camera-to-camera colour difference
%     display  rgbN with CLAHE on the Lab lightness, clip limit adapted to
%              the measured contrast (low contrast -> stronger equalisation)
%     noise    relative noise estimate; denoised = true when it exceeded
%              1.5 x cfg.quality.noiseHigh (non-local means when available)
%
%   Q (optional) is the quality struct; its contrast measurement sets the
%   CLAHE clip limit.

if nargin < 2 || isempty(cfg)
    cfg = netra.config();
end
mask = S.mask;
D = size(S.rgb, 1);
DDpx = cfg.scale.ddPerFOV * 2 * S.radius;
sigmaBG = cfg.enhance.backgroundDD * DDpx;

rgb = netra.util.fillOutside(S.rgb, mask, 2);
G = rgb(:, :, 2);
BG = netra.quality.background(G, mask, sigmaBG);
noise = netra.quality.noiseSigma(G ./ BG, mask);

E = struct();
E.noise = noise;
E.denoised = false;
if cfg.enhance.denoise && noise > 1.5 * cfg.quality.noiseHigh
    for k = 1:3
        ch = rgb(:, :, k);
        if netra.util.has('imnlmfilt')
            level = noise * max(mean(ch(mask)), 0.05);
            ch = imnlmfilt(ch, 'DegreeOfSmoothing', 1.5 * level);
        else
            ch = imgaussfilt(ch, 0.8);
        end
        rgb(:, :, k) = ch;
    end
    E.denoised = true;
    G = rgb(:, :, 2);
    BG = netra.quality.background(G, mask, sigmaBG);
end

rgbN = zeros(D, D, 3);
target = cfg.enhance.targetRGB;
for k = 1:3
    if k == 2
        Bk = BG;
    else
        Bk = netra.quality.background(rgb(:, :, k), mask, sigmaBG);
    end
    rgbN(:, :, k) = min(rgb(:, :, k) ./ Bk * target(k), 1);
end
gN = rgb(:, :, 2) ./ BG;
gN(~mask) = 1;

% display image: CLAHE on Lab lightness, clip adapted to measured contrast
clip = cfg.enhance.claheClip;
if nargin >= 3 && isstruct(Q) && isfield(Q, 'metrics') && isfield(Q.metrics, 'contrast')
    clip = clip * min(max(cfg.quality.contrastCenter * 2 / max(Q.metrics.contrast, eps), 0.6), 2.5);
end
lab = rgb2lab(rgbN);
Lc = adapthisteq(min(max(lab(:, :, 1) / 100, 0), 1), 'NumTiles', cfg.enhance.claheTiles, ...
    'ClipLimit', clip);
lab(:, :, 1) = Lc * 100;
disp = min(max(lab2rgb(lab), 0), 1);
for k = 1:3
    ch = disp(:, :, k);
    ch(~mask) = 0;
    disp(:, :, k) = ch;
    ch = rgbN(:, :, k);
    ch(~mask) = 0;
    rgbN(:, :, k) = ch;
end

E.gN = gN;
E.rgbN = rgbN;
E.display = disp;
E.backgroundG = BG;
E.clip = clip;
E.mask = mask;
end
