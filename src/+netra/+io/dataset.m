function D = dataset(name, root, file, id)
%DATASET Common layout every dataset adapter returns.
%
%   D = netra.io.dataset(name, root, file, id) with one row per photograph:
%     file, id          full path and identifier (n x 1 cellstr)
%     grade             ICDR-style DR grade 0..4 (NaN = not provided)
%     dme               macular-oedema grade on the dataset's own scale
%     dmeReferable      1 / 0 / NaN - referable DME as the dataset defines it
%     gradable          1 / 0 / NaN - adjudicated image gradability
%     referable         grade >= 2 or referable DME (NaN when unknown)
%     split             'train' / 'test' / 'labelled' ... as distributed
%     patient, eye      grouping for patient-level splits and analyses
%   Adapters add their own fields (lesion masks, disc and fovea centres,
%   vessel ground truth). netra.io.subset indexes all of them together.
file = file(:);
n = numel(file);
if nargin < 4 || isempty(id)
    id = cell(n, 1);
    for i = 1:n
        [~, id{i}] = fileparts(file{i});
    end
end
nanv = NaN(n, 1);
D = struct('name', name, 'root', root, 'n', n, 'file', {file}, 'id', {id(:)}, ...
    'grade', nanv, 'dme', nanv, 'dmeReferable', nanv, 'gradable', nanv, ...
    'referable', nanv, 'split', {repmat({''}, n, 1)}, 'patient', {id(:)}, ...
    'eye', {repmat({''}, n, 1)});
end
