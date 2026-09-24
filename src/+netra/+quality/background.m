function B = background(ch, mask, sigma)
%BACKGROUND Robust estimate of the smooth fundus background of one channel.
%
%   B = netra.quality.background(ch, mask, sigma) works at quarter
%   resolution in two passes: a median filter gives a first estimate that
%   ignores thin vessels and small lesions; pixels deviating by more than
%   2.5 robust sigmas from it (vessels, haemorrhages, exudates, the disc)
%   are then excluded and the background is re-estimated by normalised
%   convolution (Foracchia, Grisan & Ruggeri, Med Image Anal 2005). The
%   result is smooth, has no dark halo around the disc, and is defined
%   everywhere (outside the FOV it is extrapolated).

f = 4;
small = netra.util.imscale(netra.util.fillOutside(ch, mask), 1 / f);
msmall = netra.util.imscale(double(mask), 1 / f) > 0.5;
if ~any(msmall(:))
    B = ones(size(ch)) * max(mean(ch(mask)), eps);
    return
end
s = max(sigma / f, 2);
k = 2 * round(0.75 * s) + 1;
B1 = medfilt2(small, [k k], 'symmetric');
rel = small ./ max(B1, 1e-3) - 1;
[~, rs] = netra.util.robustStats(rel(msmall));
w = msmall & abs(rel) < 2.5 * max(rs, 0.01);
B2 = netra.util.maskedSmooth(small, w, s);
B = imresize(B2, size(ch), 'bilinear');
B = max(B, 1e-3);
end
