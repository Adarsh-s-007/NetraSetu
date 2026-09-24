function p = softmax(z, dim)
%SOFTMAX Numerically stable softmax along DIM (default: 2, rows are samples).
if nargin < 2
    dim = 2;
end
z = z - max(z, [], dim);
e = exp(z);
p = e ./ sum(e, dim);
end
