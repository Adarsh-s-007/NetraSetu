function s = opts(defaults, varargin)
%OPTS Merge name-value pairs (or a struct) into a struct of defaults.
%   s = netra.util.opts(defaults, 'Name', value, ...) replaces the matching
%   fields of DEFAULTS. Names are case-insensitive; unknown names are an
%   error so that a typo never silently falls back to a default.
s = defaults;
if numel(varargin) == 1 && isstruct(varargin{1})
    ov = varargin{1};
    f = fieldnames(ov);
    args = cell(1, 2 * numel(f));
    for k = 1:numel(f)
        args{2 * k - 1} = f{k};
        args{2 * k} = ov.(f{k});
    end
    varargin = args;
end
if mod(numel(varargin), 2) ~= 0
    error('netra:opts:pairs', 'Options must be given as name-value pairs.');
end
names = fieldnames(defaults);
for k = 1:2:numel(varargin)
    key = varargin{k};
    if isa(key, 'string')
        key = char(key);
    end
    if ~ischar(key)
        error('netra:opts:name', 'Option names must be text.');
    end
    hit = find(strcmpi(names, key), 1);
    if isempty(hit)
        error('netra:opts:unknown', 'Unknown option "%s". Valid options: %s.', ...
            key, strjoin(names', ', '));
    end
    s.(names{hit}) = varargin{k + 1};
end
end
