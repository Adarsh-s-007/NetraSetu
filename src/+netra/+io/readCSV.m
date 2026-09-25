function T = readCSV(file)
%READCSV Robust reader for the label files that ship with public datasets.
%
%   T = netra.io.readCSV(file) returns T.header (1 x m cellstr, trimmed)
%   and T.cells (n x m cellstr). Handles a UTF-8 byte-order mark, CRLF line
%   ends, comma or semicolon delimiters (detected from the header), quoted
%   fields with embedded delimiters, trailing empty columns and blank rows
%   (IDRiD's spreadsheets export all of these). Use netra.io.column to pick
%   a column by any of several header spellings.
txt = fileread(file);
if numel(txt) >= 3 && all(double(txt(1:3)) == [239 187 191])
    txt = txt(4:end);
end
if ~isempty(txt) && double(txt(1)) == 65279
    txt = txt(2:end);
end
lines = regexp(txt, '\r\n|\n|\r', 'split');
lines = lines(~cellfun(@(s) isempty(regexprep(s, '[,;\s"]', '')), lines));
if isempty(lines)
    T = struct('header', {{}}, 'cells', {cell(0, 0)});
    return
end
delim = ',';
if sum(lines{1} == ';') > sum(lines{1} == ',')
    delim = ';';
end
rows = cellfun(@(s) splitLine(s, delim), lines, 'UniformOutput', false);
m = max(cellfun(@numel, rows));
cells = repmat({''}, numel(rows), m);
for i = 1:numel(rows)
    cells(i, 1:numel(rows{i})) = rows{i};
end
cells = strtrim(cells);
% drop columns that are empty everywhere (trailing commas)
keep = any(~cellfun(@isempty, cells), 1);
cells = cells(:, keep);
T = struct('header', {cells(1, :)}, 'cells', {cells(2:end, :)});
end

function f = splitLine(s, delim)
if ~any(s == '"')
    f = regexp(s, delim, 'split');
    return
end
f = {};
cur = '';
inQ = false;
i = 1;
while i <= numel(s)
    c = s(i);
    if inQ
        if c == '"' && i < numel(s) && s(i + 1) == '"'
            cur(end + 1) = '"'; %#ok<AGROW>
            i = i + 1;
        elseif c == '"'
            inQ = false;
        else
            cur(end + 1) = c; %#ok<AGROW>
        end
    elseif c == '"'
        inQ = true;
    elseif c == delim
        f{end + 1} = cur; %#ok<AGROW>
        cur = '';
    else
        cur(end + 1) = c; %#ok<AGROW>
    end
    i = i + 1;
end
f{end + 1} = cur;
end
