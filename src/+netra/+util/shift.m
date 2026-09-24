function J = shift(I, dy, dx)
%SHIFT Integer translation with replicated borders: J(r, c) = I(r - dy, c - dx).
[h, w] = size(I);
rows = min(max((1:h) - dy, 1), h);
cols = min(max((1:w) - dx, 1), w);
J = I(rows, cols);
end
