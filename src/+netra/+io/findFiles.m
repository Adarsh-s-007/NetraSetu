function files = findFiles(root, pattern, maxDepth)
%FINDFILES Files under ROOT whose name matches a regular expression.
%   files = netra.io.findFiles(root, '^\d+_test\.tif$')        depth 6
%   files = netra.io.findFiles(root, pattern, maxDepth)
%   Case-insensitive; returns full paths (column cell, sorted). Hidden
%   entries and macOS resource forks ('._*') are skipped. Works the same in
%   MATLAB and Octave (no reliance on dir('**')).
if nargin < 3
    maxDepth = 6;
end
files = {};
if isempty(root) || ~exist(root, 'dir')
    return
end
stack = {root};
depth = 0;
while ~isempty(stack) && depth <= maxDepth
    next = {};
    for i = 1:numel(stack)
        d = dir(stack{i});
        for k = 1:numel(d)
            n = d(k).name;
            if n(1) == '.' || strncmp(n, '._', 2)
                continue
            end
            p = fullfile(stack{i}, n);
            if d(k).isdir
                next{end + 1} = p; %#ok<AGROW>
            elseif ~isempty(regexpi(n, pattern, 'once'))
                files{end + 1, 1} = p; %#ok<AGROW>
            end
        end
    end
    stack = next;
    depth = depth + 1;
end
files = sort(files);
end
