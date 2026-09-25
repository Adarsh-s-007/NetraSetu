function D = aptos(root)
%APTOS APTOS 2019 Blindness Detection (Aravind Eye Hospital, via Kaggle).
%
%   D = netra.io.aptos()          looks in <NETRA_DATA or repo>/data/APTOS2019
%   D = netra.io.aptos(folder)
%
%   Expects the Kaggle layout: train.csv (id_code, diagnosis) and a folder
%   of <id_code>.png images (train_images/). The 3,662 labelled images are
%   returned with split 'labelled'; experiments split them by patient-free
%   stratified sampling (APTOS publishes no patient identifiers, and a
%   known share of its images are duplicates - keep that in mind when
%   reading internal-validation results). Grades 0-4 follow the ICDR scale;
%   no DME label is provided, so 'referable' is grade >= 2.
%   https://www.kaggle.com/c/aptos2019-blindness-detection
if nargin < 1
    root = '';
end
root = netra.io.dataRoot('APTOS2019', root);
csv = netra.io.findFiles(root, '^train(_1)?\.csv$', 3);
if isempty(csv)
    error('netra:io:aptos', ['APTOS 2019 labels (train.csv) not found under %s. ' ...
        'Download the competition data from Kaggle and unzip it there (see data/README.md).'], root);
end
T = netra.io.readCSV(csv{1});
ids = netra.io.column(T, {'id_code', 'id', 'image'});
g = netra.io.column(T, {'diagnosis', 'grade', 'level'}, 'num');
if isempty(ids) || isempty(g)
    error('netra:io:aptos', 'Unexpected columns in %s.', csv{1});
end
imgs = netra.io.findFiles(root, '\.(png|jpe?g|tiff?)$', 4);
file = matchByName(ids, imgs, 'train');
D = netra.io.dataset('APTOS2019', root, file, ids);
D.grade = g;
D.split = repmat({'labelled'}, D.n, 1);
D = netra.io.finalize(D);
end

function file = matchByName(ids, imgs, prefer)
% basename lookup; when a name occurs twice prefer the path containing PREFER
names = cell(numel(imgs), 1);
for k = 1:numel(imgs)
    [~, names{k}] = fileparts(imgs{k});
end
names = lower(names);
file = repmat({''}, numel(ids), 1);
[s, order] = sort(names);
for i = 1:numel(ids)
    key = lower(ids{i});
    [~, e] = fileparts(key);                % ids may carry an extension
    if ~isempty(e) && any(strcmpi(['.' e], {'.png', '.jpg', '.jpeg', '.tif', '.tiff'}))
        key = key(1:end - numel(e) - 1);
    end
    lo = find(strcmp(s, key));
    if isempty(lo)
        continue
    end
    cand = imgs(order(lo));
    j = find(~cellfun(@isempty, strfind(lower(cand), prefer)), 1);
    if isempty(j)
        j = 1;
    end
    file{i} = cand{j};
end
end
