function D = finalize(D, dropMissing)
%FINALIZE Derive the referable label and drop rows whose image is missing.
%   D = netra.io.finalize(D) sets D.referable = grade >= 2 OR referable
%   DME (NaN when neither is known), makes ungradable eyes unlabelled for
%   grading, and removes rows without an image file (with a warning), so
%   experiments never silently evaluate on a partial dataset.
if nargin < 2
    dropMissing = true;
end
g = D.grade;
r = double(g >= 2);
r(isnan(g)) = NaN;
dr = D.dmeReferable;
r(dr == 1) = 1;
r(isnan(g) & dr == 0) = NaN;
r(D.gradable == 0) = NaN;
D.referable = r;
if dropMissing
    ok = ~cellfun(@isempty, D.file);
    for i = find(ok)'
        ok(i) = exist(D.file{i}, 'file') == 2;
    end
    if any(~ok)
        warning('netra:io:missing', '%s: %d of %d listed images were not found and are excluded.', ...
            D.name, nnz(~ok), numel(ok));
        D = netra.io.subset(D, find(ok));
    end
end
D.n = numel(D.file);
end
