function tf = contains(str, pattern, varargin)
%CONTAINS Octave shim (char / cellstr input, char or cellstr patterns).
ignore = numel(varargin) >= 2 && strcmpi(varargin{1}, 'IgnoreCase') && varargin{2};
if ischar(pattern)
    pattern = {pattern};
end
if ischar(str)
    str = {str};
    single = true;
else
    single = false;
end
tf = false(size(str));
for i = 1:numel(str)
    s = str{i};
    for j = 1:numel(pattern)
        if ignore
            hit = ~isempty(strfind(lower(s), lower(pattern{j})));
        else
            hit = ~isempty(strfind(s, pattern{j}));
        end
        if hit
            tf(i) = true;
            break
        end
    end
end
if single
    tf = tf(1);
end
end
