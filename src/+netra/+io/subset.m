function D = subset(D, idx)
%SUBSET Rows IDX (indices or logical) of a dataset, all per-image fields together.
if islogical(idx)
    idx = find(idx);
end
n = D.n;
D = pick(D, idx, n);
D.n = numel(idx);
end

function s = pick(s, idx, n)
f = fieldnames(s);
for k = 1:numel(f)
    v = s.(f{k});
    if isstruct(v) && isscalar(v)
        s.(f{k}) = pick(v, idx, n);
    elseif (iscell(v) || isnumeric(v) || islogical(v)) && size(v, 1) == n && ~strcmp(f{k}, 'n')
        s.(f{k}) = v(idx, :);
    end
end
end
