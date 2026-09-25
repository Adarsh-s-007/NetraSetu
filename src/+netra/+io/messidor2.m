function D = messidor2(root)
%MESSIDOR2 Messidor-2 (Decenciere et al., Image Anal Stereol 2014; ADCIS).
%
%   D = netra.io.messidor2()      looks in <NETRA_DATA or repo>/data/Messidor-2
%   D = netra.io.messidor2(folder)
%
%   1,748 macula-centred photographs of 874 examinations (both eyes),
%   Topcon TRC NW6 45 degrees, France. The images ship without grades; the
%   widely used adjudicated grades (Krause et al., Ophthalmology 2018) are
%   distributed as messidor_data.csv (image_id, adjudicated_dr_grade,
%   adjudicated_dme, adjudicated_gradable) - place that file anywhere under
%   the folder. Referable = moderate NPDR or worse, or referable DME, the
%   definition used by Gulshan et al. (JAMA 2016) and Abramoff et al.
%   (IOVS 2016). Examination pairs are read from the ADCIS spreadsheet
%   exported as CSV (messidor-2.csv: one row per examination listing the
%   two image names), so analyses can be done per patient; without it every
%   image is its own patient.
%   https://www.adcis.net/en/third-party/messidor2/
if nargin < 1
    root = '';
end
root = netra.io.dataRoot('Messidor2', root);
imgs = netra.io.findFiles(root, '\.(png|jpe?g|tiff?)$', 4);
if isempty(imgs)
    error('netra:io:messidor2', 'Messidor-2 images not found under %s.', root);
end
names = cell(numel(imgs), 1);
for k = 1:numel(imgs)
    [~, n, e] = fileparts(imgs{k});
    names{k} = lower([n e]);
end
D = netra.io.dataset('Messidor-2', root, imgs, names);
D.split = repmat({'external'}, D.n, 1);
csvs = netra.io.findFiles(root, '\.csv$', 4);
labelled = false;
for c = 1:numel(csvs)
    T = netra.io.readCSV(csvs{c});
    [g, jg] = netra.io.column(T, {'adjudicated_dr_grade', 'dr_grade', 'grade'}, 'num');
    if jg > 0
        id = lower(netra.io.column(T, {'image_id', 'image', 'image_name'}));
        m = netra.io.column(T, {'adjudicated_dme', 'dme'}, 'num');
        q = netra.io.column(T, {'adjudicated_gradable', 'gradable'}, 'num');
        [tf, loc] = ismember(D.id, id);
        D.grade(tf) = g(loc(tf));
        if ~isempty(m)
            D.dme(tf) = m(loc(tf));
            D.dmeReferable(tf) = double(m(loc(tf)) >= 1);
            D.dmeReferable(tf & isnan(D.dme)) = NaN;
        end
        if ~isempty(q)
            D.gradable(tf) = q(loc(tf));
        end
        labelled = true;
    else
        D = pairs(D, T);
    end
end
if ~labelled
    warning('netra:io:messidor2', ['No adjudicated grades (messidor_data.csv) under %s: ' ...
        'images are listed without labels.'], root);
end
D = netra.io.finalize(D);
end

function D = pairs(D, T)
% rows that name two of the images are one examination (left + right eye)
hl = find(~cellfun(@isempty, regexpi(T.header, 'left', 'once')), 1);
hr = find(~cellfun(@isempty, regexpi(T.header, 'right', 'once')), 1);
for r = 1:size(T.cells, 1)
    cells = lower(T.cells(r, :));
    [tf, loc] = ismember(cells, D.id);
    if nnz(tf) >= 2
        idx = loc(tf);
        pid = sprintf('exam%04d', r);
        D.patient(idx) = {pid};
        if ~isempty(hl) && tf(hl)
            D.eye{loc(hl)} = 'L';
        end
        if ~isempty(hr) && tf(hr)
            D.eye{loc(hr)} = 'R';
        end
    end
end
end
