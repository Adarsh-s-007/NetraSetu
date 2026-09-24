function M = boxMean(A, w)
%BOXMEAN Mean over a w x w window (separable, zero-padded, 'same' size).
k = ones(w, 1) / w;
M = conv2(k, k', A, 'same');
end
