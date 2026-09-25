function D = drive(root)
%DRIVE Digital Retinal Images for Vessel Extraction (Staal et al., IEEE TMI 2004).
%
%   D = netra.io.drive()          looks in <NETRA_DATA or repo>/data/DRIVE
%   D = netra.io.drive(folder)
%
%   40 photographs (565 x 584, Canon CR5 45 degrees, Dutch screening
%   programme): training/ 21-40 and test/ 01-20, with manual vessel
%   segmentations (1st_manual; 2nd_manual for the test set, the "second
%   observer") and FOV masks. D.gt, D.gt2 and D.fov hold the file names
%   ('' when absent - the grand-challenge release withholds test labels).
%   https://drive.grand-challenge.org/
if nargin < 1
    root = '';
end
root = netra.io.dataRoot('DRIVE', root);
imgs = netra.io.findFiles(root, '^\d+_(training|test)\.(tiff?|png|jpe?g)$', 5);
if isempty(imgs)
    error('netra:io:drive', 'DRIVE images (NN_training.tif / NN_test.tif) not found under %s.', root);
end
num = cell(numel(imgs), 1);
sp = cell(numel(imgs), 1);
for k = 1:numel(imgs)
    [~, nm] = fileparts(imgs{k});
    tok = regexp(nm, '^(\d+)_(\w+)$', 'tokens', 'once');
    num{k} = sprintf('%02d', str2double(tok{1}));
    sp{k} = 'train';
    if strcmpi(tok{2}, 'test')
        sp{k} = 'test';
    end
end
D = netra.io.dataset('DRIVE', root, imgs, num);
D.split = sp;
D.gt = lookup(num, netra.io.findFiles(root, '^\d+_manual1\.(gif|png|tiff?)$', 5));
D.gt2 = lookup(num, netra.io.findFiles(root, '^\d+_manual2\.(gif|png|tiff?)$', 5));
D.fov = lookup(num, netra.io.findFiles(root, '^\d+_(training|test)_mask\.(gif|png|tiff?)$', 5));
D = netra.io.finalize(D);
end

function out = lookup(num, files)
out = repmat({''}, numel(num), 1);
for k = 1:numel(files)
    [~, nm] = fileparts(files{k});
    n = sprintf('%02d', str2double(regexp(nm, '^\d+', 'match', 'once')));
    out(strcmp(num, n)) = files(k);
end
end
