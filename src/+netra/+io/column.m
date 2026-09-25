function [v, j] = column(T, names, kind)
%COLUMN One column of a netra.io.readCSV table, found by header spelling.
%   v = netra.io.column(T, {'id_code', 'image'})            cellstr
%   v = netra.io.column(T, {'diagnosis', 'grade'}, 'num')   double (NaN if blank)
%   Headers are compared after lower-casing and removing everything that is
%   not a letter or digit, so 'Risk of macular edema ' matches
%   'riskofmacularedema'. Returns [] (and j = 0) when no column matches.
if ischar(names)
    names = {names};
end
if nargin < 3
    kind = 'str';
end
norm = @(s) lower(regexprep(s, '[^A-Za-z0-9]', ''));
h = cellfun(norm, T.header, 'UniformOutput', false);
j = 0;
for k = 1:numel(names)
    j = find(strcmp(h, norm(names{k})), 1);
    if ~isempty(j)
        break
    end
end
if isempty(j)
    j = 0;
    v = [];
    return
end
v = T.cells(:, j);
if strcmp(kind, 'num')
    v = str2double(v);
end
end
