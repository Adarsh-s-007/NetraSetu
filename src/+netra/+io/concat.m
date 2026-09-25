function D = concat(A, B, name)
%CONCAT Stack two datasets (their common per-image fields) into one.
%   D = netra.io.concat(A, B, name) - e.g. APTOS training images plus
%   IDRiD training images for grader training. Dataset-specific fields that
%   only one of them has (masks, landmarks) are dropped.
if nargin < 3
    name = [A.name '+' B.name];
end
fa = fieldnames(A);
fb = fieldnames(B);
common = fa(ismember(fa, fb));
D = struct('name', name, 'root', '', 'n', A.n + B.n);
for k = 1:numel(common)
    f = common{k};
    a = A.(f);
    b = B.(f);
    if any(strcmp(f, {'name', 'root', 'n'})) || isstruct(a)
        continue
    end
    if size(a, 1) == A.n && size(b, 1) == B.n && size(a, 2) == size(b, 2)
        D.(f) = [a; b];
    end
end
end
