function s = split(D, fractions, names, seed)
%SPLIT Patient-grouped, grade-stratified random split.
%   s = netra.io.split(D, [0.7 0.15 0.15], {'train', 'val', 'test'}, seed)
%   returns an n x 1 cellstr. All photographs of a patient land in the same
%   part (D.patient), and every grade is spread over the parts in the given
%   proportions, so a validation set cannot contain the fellow eye of a
%   training patient.
if nargin < 4
    seed = 1;
end
st = rng();
rng(seed);
[pid, ~, pj] = unique(D.patient);
np = numel(pid);
pg = zeros(np, 1);                          % patient stratum: worst known grade
for p = 1:np
    g = D.grade(pj == p);
    g = g(~isnan(g));
    if isempty(g)
        pg(p) = -1;
    else
        pg(p) = max(g);
    end
end
assign = zeros(np, 1);
f = fractions(:)' / sum(fractions);
carry = zeros(size(f));
for g = unique(pg)'
    members = find(pg == g);
    members = members(randperm(numel(members)));
    m = numel(members);
    % largest-remainder allocation; the fractional remainders are carried
    % to the next stratum, so small parts (a 5 % hold-out) still receive
    % eyes and every part keeps the grade mix
    want = f * m + carry;
    n = floor(want);
    left = m - sum(n);
    [~, order] = sort(want - n, 'descend');
    n(order(1:left)) = n(order(1:left)) + 1;
    carry = want - n;
    edges = [0, cumsum(n)];
    for k = 1:numel(f)
        assign(members(edges(k) + 1:edges(k + 1))) = k;
    end
end
s = names(assign(pj));
s = s(:);
rng(st);
end
