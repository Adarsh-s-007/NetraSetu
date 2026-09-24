function J = fillOutside(I, mask, smoothSigma)
%FILLOUTSIDE Extend image content beyond the field-of-view mask.
%   J = netra.util.fillOutside(I, mask) copies the nearest in-FOV value to
%   every pixel outside MASK, then (optionally) smooths only the filled
%   region. Filtering J instead of I prevents the black camera border from
%   producing false vessels, false lesions and dark haloes at the FOV rim.
if nargin < 3
    smoothSigma = 0;
end
if all(mask(:))
    J = I;
    return
end
[~, idx] = bwdist(mask);
idx = double(idx);
J = I;
out = ~mask;
for k = 1:size(I, 3)
    plane = I(:, :, k);
    plane(out) = plane(idx(out));
    if smoothSigma > 0
        sm = imgaussfilt(plane, smoothSigma);
        plane(out) = sm(out);
    end
    J(:, :, k) = plane;
end
end
