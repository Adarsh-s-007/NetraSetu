function S = maskedSmooth(I, W, sigma)
%MASKEDSMOOTH Normalised convolution: Gaussian smoothing that ignores W == 0.
%   S = netra.util.maskedSmooth(I, W, sigma) = G*(I.W) ./ G*W. Pixels with no
%   support fall back to the unweighted smooth. Used for background
%   estimation that excludes vessels and lesions (Foracchia et al., 2005).
W = double(W);
num = netra.util.smooth(I .* W, sigma);
den = netra.util.smooth(W, sigma);
S = num ./ max(den, 1e-6);
weak = den < 1e-3;
if any(weak(:))
    plain = netra.util.smooth(I, sigma);
    S(weak) = plain(weak);
end
end
