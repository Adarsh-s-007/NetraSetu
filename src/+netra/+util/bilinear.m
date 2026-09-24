function v = bilinear(I, x, y, fill)
%BILINEAR Sample image I at real-valued (x, y) positions (x = column).
%   v = netra.util.bilinear(I, x, y, fill) - a light-weight INTERP2 for a
%   handful of points; positions outside the image return FILL.
if nargin < 4
    fill = 0;
end
[h, w] = size(I);
x0 = floor(x);
y0 = floor(y);
fx = x - x0;
fy = y - y0;
ok = x0 >= 1 & y0 >= 1 & x0 < w & y0 < h;
v = fill * ones(size(x));
if any(ok(:))
    i00 = y0(ok) + (x0(ok) - 1) * h;
    v(ok) = (1 - fx(ok)) .* (1 - fy(ok)) .* I(i00) + fx(ok) .* (1 - fy(ok)) .* I(i00 + h) + ...
            (1 - fx(ok)) .* fy(ok) .* I(i00 + 1) + fx(ok) .* fy(ok) .* I(i00 + h + 1);
end
end
