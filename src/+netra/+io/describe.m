function describe(D)
%DESCRIBE Print image counts by split and grade (and referable share).
fprintf('%s  (%d images, %d patients)  %s\n', D.name, D.n, numel(unique(D.patient)), D.root);
sp = unique(D.split);
fprintf('  %-10s %6s %6s %6s %6s %6s %6s %9s\n', 'split', 'g0', 'g1', 'g2', 'g3', 'g4', 'n/a', 'referable');
for k = 1:numel(sp)
    m = strcmp(D.split, sp{k});
    c = arrayfun(@(g) nnz(m & D.grade == g), 0:4);
    r = D.referable(m);
    fprintf('  %-10s %6d %6d %6d %6d %6d %6d %8.1f%%\n', sp{k}, c, nnz(m & isnan(D.grade)), ...
        100 * mean(r(~isnan(r))));
end
end
