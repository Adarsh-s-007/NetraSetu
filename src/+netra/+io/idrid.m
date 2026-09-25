function D = idrid(root, part)
%IDRID Indian Diabetic Retinopathy Image Dataset (Porwal et al., Data 2018).
%
%   D = netra.io.idrid()                            disease grading (part B)
%   D = netra.io.idrid(folder, 'grading')           516 images, DR 0-4 + DME 0-2
%   D = netra.io.idrid(folder, 'segmentation')      81 images with pixel masks
%   D = netra.io.idrid(folder, 'localization')      516 images, disc + fovea centres
%
%   Works with the layout of the IEEE DataPort release ("A. Segmentation",
%   "B. Disease Grading", "C. Localization", each with "a. Training Set" /
%   "b. Testing Set"), matching folders by keyword rather than exact name.
%   Images are 4288 x 2848 (Kowa VX-10 alpha, 50 degrees, Nanded, India).
%
%   grading       grade, dme (0 none, 1 exudates > 1 DD from the fovea,
%                 2 within 1 DD), dmeReferable = dme == 2, split train/test
%   segmentation  masks.MA / HE / EX / SE / OD: mask file per image ('' when
%                 the image has none of that lesion)
%   localization  od, fovea: [x y] in pixels of the original photograph
%   https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid
if nargin < 1
    root = '';
end
if nargin < 2 || isempty(part)
    part = 'grading';
end
root = netra.io.dataRoot('IDRiD', root);
if ~exist(root, 'dir')
    error('netra:io:idrid', 'IDRiD not found at %s (see data/README.md).', root);
end
imgs = netra.io.findFiles(root, '^IDRiD_\d+\.(jpe?g|png|tiff?)$', 7);
low = lower(imgs);
has = @(k) ~cellfun(@isempty, strfind(low, k));
switch lower(part)
    case 'grading'
        imgs = imgs(has('grading'));
        csvs = netra.io.findFiles(root, 'grading.*label.*\.csv$', 6);
        if isempty(csvs)
            error('netra:io:idrid', 'IDRiD grading labels (*Disease Grading*Labels.csv) not found under %s.', root);
        end
        file = {}; ids = {}; grade = []; dme = []; sp = {};
        for c = 1:numel(csvs)
            T = netra.io.readCSV(csvs{c});
            id = netra.io.column(T, {'Image name', 'image', 'imagename'});
            g = netra.io.column(T, {'Retinopathy grade', 'retinopathy'}, 'num');
            m = netra.io.column(T, {'Risk of macular edema', 'riskofmacularoedema', 'dme'}, 'num');
            s = splitOf(csvs{c});
            pool = imgs(~cellfun(@isempty, strfind(lower(imgs), s)));
            file = [file; byName(id, pool)]; %#ok<AGROW>
            ids = [ids; id]; %#ok<AGROW>
            grade = [grade; g]; %#ok<AGROW>
            dme = [dme; m]; %#ok<AGROW>
            sp = [sp; repmat({s}, numel(id), 1)]; %#ok<AGROW>
        end
        D = netra.io.dataset('IDRiD-grading', root, file, strcat(sp, '/', ids));
        D.grade = grade;
        D.dme = dme;
        D.dmeReferable = double(dme >= 2);
        D.dmeReferable(isnan(dme)) = NaN;
        D.split = sp;
    case 'segmentation'
        imgs = imgs(has('segmentation'));
        D = netra.io.dataset('IDRiD-segmentation', root, imgs);
        D.split = cellfun(@splitOf, imgs, 'UniformOutput', false);
        masks = netra.io.findFiles(root, '^IDRiD_\d+_(MA|HE|EX|SE|OD)\.(tiff?|png|jpe?g|gif)$', 8);
        types = {'MA', 'HE', 'EX', 'SE', 'OD'};
        D.masks = struct();
        for t = 1:numel(types)
            D.masks.(types{t}) = repmat({''}, D.n, 1);
        end
        for k = 1:numel(masks)
            [~, nm] = fileparts(masks{k});
            tok = regexp(nm, '^(IDRiD_\d+)_(\w+)$', 'tokens', 'once');
            i = find(strcmpi(D.id, tok{1}) & strcmp(D.split, splitOf(masks{k})));
            if isempty(i)
                i = find(strcmpi(D.id, tok{1}));
            end
            if ~isempty(i)
                D.masks.(upper(tok{2}))(i) = masks(k);
            end
        end
    case {'localization', 'localisation'}
        imgs = imgs(has('locali'));
        D = netra.io.dataset('IDRiD-localization', root, imgs);
        D.split = cellfun(@splitOf, imgs, 'UniformOutput', false);
        D.od = NaN(D.n, 2);
        D.fovea = NaN(D.n, 2);
        D.od = readCentres(D, netra.io.findFiles(root, 'od.*cent.*\.csv$', 7), D.od);
        D.fovea = readCentres(D, netra.io.findFiles(root, 'fovea.*cent.*\.csv$', 7), D.fovea);
    otherwise
        error('netra:io:idrid', 'Unknown IDRiD part ''%s''.', part);
end
D = netra.io.finalize(D);
end

% ======================================================================
function s = splitOf(p)
p = lower(p);
if ~isempty(strfind(p, 'test'))
    s = 'test';
elseif ~isempty(strfind(p, 'train'))
    s = 'train';
else
    s = 'unknown';
end
end

function file = byName(ids, pool)
names = cell(numel(pool), 1);
for k = 1:numel(pool)
    [~, names{k}] = fileparts(pool{k});
end
file = repmat({''}, numel(ids), 1);
for i = 1:numel(ids)
    j = find(strcmpi(names, ids{i}), 1);
    if ~isempty(j)
        file{i} = pool{j};
    end
end
end

function xy = readCentres(D, csvs, xy)
for c = 1:numel(csvs)
    T = netra.io.readCSV(csvs{c});
    id = netra.io.column(T, {'Image No', 'imageno', 'image', 'imagename'});
    x = netra.io.column(T, {'X- Coordinate', 'xcoordinate', 'x'}, 'num');
    y = netra.io.column(T, {'Y - Coordinate', 'ycoordinate', 'y'}, 'num');
    s = splitOf(csvs{c});
    for r = 1:numel(id)
        i = find(strcmpi(D.id, id{r}) & strcmp(D.split, s), 1);
        if ~isempty(i)
            xy(i, :) = [x(r) y(r)];
        end
    end
end
end
