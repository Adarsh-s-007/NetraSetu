% Dataset readers: CSV quirks of the public releases, column matching,
% patient-grouped splits, file discovery.
tmp = tempname();
mkdir(tmp);

%% CSV with BOM, CRLF, quotes, trailing empty columns and blank rows
f = fullfile(tmp, 'labels.csv');
fid = fopen(f, 'w');
fwrite(fid, [239 187 191]);
fprintf(fid, 'Image name,Retinopathy grade,Risk of macular edema ,,\r\n');
fprintf(fid, 'IDRiD_001,3,2,,\r\n"IDRiD_002",0,0,,\r\n,,,,\r\n"IDRiD, 003",4,1,,\r\n');
fclose(fid);
T = netra.io.readCSV(f);
assert(isequal(T.header, {'Image name', 'Retinopathy grade', 'Risk of macular edema'}));
assert(size(T.cells, 1) == 3);
ids = netra.io.column(T, {'image name'});
assert(strcmp(ids{3}, 'IDRiD, 003'));
g = netra.io.column(T, {'retinopathy_grade', 'grade'}, 'num');
assert(isequal(g(:)', [3 0 4]));
dme = netra.io.column(T, {'riskofmacularedema'}, 'num');
assert(isequal(dme(:)', [2 0 1]));

%% Semicolon-separated files are detected
f = fullfile(tmp, 'semi.csv');
fid = fopen(f, 'w');
fprintf(fid, 'left;right\nA.png;B.png\n');
fclose(fid);
T = netra.io.readCSV(f);
assert(isequal(T.header, {'left', 'right'}) && strcmp(T.cells{1, 2}, 'B.png'));

%% Missing columns return empty rather than failing
T = struct('header', {{'a', 'b'}}, 'cells', {{'1', '2'}});
[v, j] = netra.io.column(T, {'zzz'});
assert(isempty(v) && j == 0);

%% findFiles searches recursively, case-insensitively, and skips hidden files
mkdir(fullfile(tmp, 'x', 'Y'));
fclose(fopen(fullfile(tmp, 'x', 'Y', '21_Training.TIF'), 'w'));
fclose(fopen(fullfile(tmp, 'x', '._21_training.tif'), 'w'));
files = netra.io.findFiles(tmp, '^\d+_training\.tif$');
assert(numel(files) == 1 && ~isempty(strfind(files{1}, '21_Training.TIF')));

%% Splits keep a patient's eyes together and follow the proportions
D = netra.io.dataset('t', tmp, arrayfun(@(i) sprintf('f%d', i), (1:400)', 'UniformOutput', false));
D.patient = arrayfun(@(i) sprintf('p%d', ceil(i / 2)), (1:400)', 'UniformOutput', false);
D.grade = mod((0:399)', 5);
s = netra.io.split(D, [0.7 0.2 0.1], {'a', 'b', 'c'}, 3);
for p = 1:200
    m = strcmp(D.patient, sprintf('p%d', p));
    assert(numel(unique(s(m))) == 1, 'patient %d split across parts', p);
end
share = [mean(strcmp(s, 'a')), mean(strcmp(s, 'b')), mean(strcmp(s, 'c'))];
assert(max(abs(share - [0.7 0.2 0.1])) < 0.03, 'shares %s', mat2str(share, 3));

%% Referable = grade >= 2 or referable DME; unknown stays unknown
D = netra.io.dataset('t', tmp, {'a'; 'b'; 'c'; 'd'; 'e'});
D.grade = [0; 1; 2; NaN; 1];
D.dmeReferable = [0; 1; 0; 0; NaN];
D.gradable = [1; 1; 1; 1; 0];
D = netra.io.finalize(D, false);
assert(isequaln(D.referable', [0 1 1 NaN NaN]));

%% subset indexes every per-image field together, including nested masks
D = netra.io.dataset('t', tmp, {'a'; 'b'; 'c'});
D.masks = struct('MA', {{'m1'; ''; 'm3'}});
E = netra.io.subset(D, [3 1]);
assert(E.n == 2 && isequal(E.file', {'c', 'a'}) && isequal(E.masks.MA', {'m3', 'm1'}));

%% Masks: GIF palette, 0/1 PNG and coloured TIFF all read as logical
m = false(20);
m(5:10, 6:12) = true;
imwrite(uint8(255 * m), fullfile(tmp, 'm.gif'));
imwrite(uint8(m), fullfile(tmp, 'm.png'));
c = zeros(20, 20, 3, 'uint8');
c(:, :, 1) = uint8(255 * m);
imwrite(c, fullfile(tmp, 'm.tif'));
assert(isequal(netra.io.readMask(fullfile(tmp, 'm.gif')), m));
assert(isequal(netra.io.readMask(fullfile(tmp, 'm.png')), m));
assert(isequal(netra.io.readMask(fullfile(tmp, 'm.tif')), m));
