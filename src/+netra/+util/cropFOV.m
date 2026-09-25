function img = cropFOV(img, c, r)
%CROPFOV Square crop around a circular field of view (centre c = [x y], radius r).
r = r * 1.02;
H = size(img, 1);
W = size(img, 2);
r1 = max(1, round(c(2) - r)); r2 = min(H, round(c(2) + r));
c1 = max(1, round(c(1) - r)); c2 = min(W, round(c(1) + r));
img = img(r1:r2, c1:c2, :);
end
