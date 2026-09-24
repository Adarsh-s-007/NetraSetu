function y = sigmoid(x, centre, width)
%SIGMOID Logistic function, optionally shifted and scaled.
%   y = netra.util.sigmoid(x)                 1 ./ (1 + exp(-x))
%   y = netra.util.sigmoid(x, centre, width)  1 ./ (1 + exp(-(x - centre) ./ width))
if nargin > 1
    x = (x - centre) ./ width;
end
y = 1 ./ (1 + exp(-x));
end
