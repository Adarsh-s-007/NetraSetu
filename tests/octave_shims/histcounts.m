function [n, edges] = histcounts(x, edges)
%HISTCOUNTS Octave shim (explicit bin edges only; last bin closed).
x = x(:);
n = zeros(1, numel(edges) - 1);
for k = 1:numel(edges) - 1
    if k < numel(edges) - 1
        n(k) = sum(x >= edges(k) & x < edges(k + 1));
    else
        n(k) = sum(x >= edges(k) & x <= edges(k + 1));
    end
end
end
