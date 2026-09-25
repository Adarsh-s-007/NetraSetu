function root = makeFakeDatasets(root, varargin)
%MAKEFAKEDATASETS Miniature APTOS / IDRiD / DRIVE / Messidor-2 trees from phantoms.
%
%   root = makeFakeDatasets(tempdir-folder)
%   root = makeFakeDatasets(folder, 'Size', 640, 'N', 6)
%
%   Writes synthetic photographs (netra.phantom.generate) with their ground
%   truth in the SAME folder layout and file formats as the public
%   releases, so the dataset adapters and every experiment script can be
%   exercised end to end without the real data (smoke test, not
%   validation):
%     APTOS2019/train.csv, train_images/<id>.png
%     IDRiD/A. Segmentation/... (images, MA/HE/EX/SE/OD masks)
%     IDRiD/B. Disease Grading/... (images, label CSVs)
%     IDRiD/C. Localization/... (images, OD and fovea centre CSVs)
%     DRIVE/training|test/images|1st_manual|2nd_manual|mask
%     Messidor-2/IMAGES/*.png, messidor_data.csv, messidor-2.csv
o = netra.util.opts(struct('Size', 640, 'N', 6), varargin{:});
if ~exist(root, 'dir')
    mkdir(root);
end
sz = o.Size;
grades = mod(0:max(o.N, 6) - 1, 5);
k = 0;
    function [rgb, gt] = phantomEye(g, seed)
        [rgb, gt] = netra.phantom.generate('Size', sz, 'Seed', seed, 'Grade', g, ...
            'Eye', char('R' + ('L' - 'R') * mod(seed, 2)));
    end
    function d = md(varargin)
        d = fullfile(root, varargin{:});
        if ~exist(d, 'dir')
            mkdir(d);
        end
    end
    function writeCSV(file, header, rows)
        fid = fopen(file, 'w');
        fprintf(fid, '%s\n', header);
        for r = 1:size(rows, 1)
            fprintf(fid, '%s\n', strjoin(rows(r, :), ','));
        end
        fclose(fid);
    end

% ------------------------------------------------------------- APTOS
d = md('APTOS2019', 'train_images');
rows = cell(0, 2);
for i = 1:o.N
    k = k + 1;
    id = sprintf('%012x', 2 ^ 40 + 7919 * k);
    [rgb, gt] = phantomEye(grades(i), 100 + k);
    imwrite(rgb, fullfile(d, [id '.png']));
    rows(end + 1, :) = {id, sprintf('%d', gt.grade)}; %#ok<AGROW>
end
writeCSV(fullfile(root, 'APTOS2019', 'train.csv'), 'id_code,diagnosis', rows);

% ------------------------------------------------------------- IDRiD
base = 'IDRiD';
for s = {'a. Training Set', 'b. Testing Set'}
    isTest = s{1}(1) == 'b';
    % grading
    d = md(base, 'B. Disease Grading', '1. Original Images', s{1});
    rows = cell(0, 3);
    for i = 1:max(3, floor(o.N / 2))
        k = k + 1;
        name = sprintf('IDRiD_%03d', i);
        [rgb, gt] = phantomEye(grades(i), 200 + k);
        imwrite(rgb, fullfile(d, [name '.jpg']), 'Quality', 95);
        rows(end + 1, :) = {name, sprintf('%d', gt.grade), sprintf('%d', gt.dme)}; %#ok<AGROW>
    end
    g = md(base, 'B. Disease Grading', '2. Groundtruths');
    tag = 'Training';
    if isTest
        tag = 'Testing';
    end
    rows(:, 3) = strcat(rows(:, 3), ',,');           % IDRiD's export has trailing empty columns
    writeCSV(fullfile(g, sprintf('%s. IDRiD_Disease Grading_%s Labels.csv', s{1}(1), tag)), ...
        'Image name,Retinopathy grade,Risk of macular edema ,,', rows);
    % segmentation
    d = md(base, 'A. Segmentation', '1. Original Images', s{1});
    types = {'1. Microaneurysms', 'MA', 'maMask'; '2. Haemorrhages', 'HE', 'heMask'; ...
        '3. Hard Exudates', 'EX', 'exMask'; '4. Soft Exudates', 'SE', 'cwsMask'; '5. Optic Disc', 'OD', ''};
    for i = 1:2
        k = k + 1;
        num = 1 + i + 54 * isTest;
        name = sprintf('IDRiD_%02d', num);
        [rgb, gt] = phantomEye(2 + i, 300 + k);
        imwrite(rgb, fullfile(d, [name '.jpg']), 'Quality', 95);
        for t = 1:size(types, 1)
            if isempty(types{t, 3})
                [X, Y] = meshgrid(1:sz, 1:sz);
                m = hypot(X - gt.od(1), Y - gt.od(2)) <= gt.odRadius;
            else
                m = gt.(types{t, 3});
            end
            if any(m(:))
                gd = md(base, 'A. Segmentation', '2. All Segmentation Groundtruths', s{1}, types{t, 1});
                rgbm = zeros(sz, sz, 3, 'uint8');
                rgbm(:, :, 1) = uint8(255 * m);
                imwrite(rgbm, fullfile(gd, sprintf('%s_%s.tif', name, types{t, 2})));
            end
        end
    end
    % localisation
    d = md(base, 'C. Localization', '1. Original Images', s{1});
    od = cell(0, 3);
    fv = cell(0, 3);
    for i = 1:3
        k = k + 1;
        name = sprintf('IDRiD_%03d', i);
        [rgb, gt] = phantomEye(mod(i, 3), 400 + k);
        imwrite(rgb, fullfile(d, [name '.jpg']), 'Quality', 95);
        od(end + 1, :) = {name, sprintf('%.0f', gt.od(1)), sprintf('%.0f', gt.od(2))}; %#ok<AGROW>
        fv(end + 1, :) = {name, sprintf('%.0f', gt.fovea(1)), sprintf('%.0f', gt.fovea(2))}; %#ok<AGROW>
    end
    g1 = md(base, 'C. Localization', '2. Groundtruths', '1. Optic Disc Center Location');
    g2 = md(base, 'C. Localization', '2. Groundtruths', '2. Fovea Center Location');
    writeCSV(fullfile(g1, sprintf('%s. IDRiD_OD_Center_%s Set_Markups.csv', s{1}(1), tag)), ...
        'Image No,X- Coordinate,Y - Coordinate', od);
    writeCSV(fullfile(g2, sprintf('%s. IDRiD_Fovea_Center_%s Set_Markups.csv', s{1}(1), tag)), ...
        'Image No,X- Coordinate,Y - Coordinate', fv);
end

% ------------------------------------------------------------- DRIVE
for s = {'training', 'test'}
    isTest = strcmp(s{1}, 'test');
    for i = 1:2
        k = k + 1;
        num = i + 20 * ~isTest;
        [rgb, gt] = netra.phantom.generate('Size', 584, 'Seed', 500 + k, 'Grade', 0);
        c = 10:574;                                    % DRIVE images are 565 x 584
        imwrite(rgb(:, c, :), fullfile(md('DRIVE', s{1}, 'images'), sprintf('%02d_%s.tif', num, s{1})));
        imwrite(uint8(255 * gt.vessels(:, c)), fullfile(md('DRIVE', s{1}, '1st_manual'), ...
            sprintf('%02d_manual1.gif', num)));
        imwrite(uint8(255 * gt.fov(:, c)), fullfile(md('DRIVE', s{1}, 'mask'), ...
            sprintf('%02d_%s_mask.gif', num, s{1})));
        if isTest
            v2 = imdilate(gt.vessels, strel('disk', 1, 0)) & ~(rand(size(gt.vessels)) < 0.05);
            imwrite(uint8(255 * v2(:, c)), fullfile(md('DRIVE', s{1}, '2nd_manual'), ...
                sprintf('%02d_manual2.gif', num)));
        end
    end
end

% --------------------------------------------------------- Messidor-2
d = md('Messidor-2', 'IMAGES');
rows = cell(0, 4);
pairs = cell(0, 2);
for i = 1:2:o.N
    names = cell(1, 2);
    for e = 1:2
        k = k + 1;
        names{e} = sprintf('2005%04d_%05d_0100_PP.png', i, k);
        [rgb, gt] = phantomEye(grades(mod(i + e - 2, numel(grades)) + 1), 600 + k);
        imwrite(rgb, fullfile(d, names{e}));
        rows(end + 1, :) = {names{e}, sprintf('%d', gt.grade), sprintf('%d', gt.dme >= 1), '1'}; %#ok<AGROW>
    end
    pairs(end + 1, :) = names; %#ok<AGROW>
end
writeCSV(fullfile(root, 'Messidor-2', 'messidor_data.csv'), ...
    'image_id,adjudicated_dr_grade,adjudicated_dme,adjudicated_gradable', rows);
writeCSV(fullfile(root, 'Messidor-2', 'messidor-2.csv'), 'left,right', pairs);
end
