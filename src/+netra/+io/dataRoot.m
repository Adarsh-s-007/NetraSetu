function root = dataRoot(name, root)
%DATAROOT Folder that holds a public dataset.
%   root = netra.io.dataRoot('IDRiD')          <NETRA_DATA>/IDRiD, else
%                                              <repo>/data/IDRiD
%   root = netra.io.dataRoot('IDRiD', folder)  folder as given
%   Folder names are matched case-insensitively and ignoring punctuation,
%   so 'aptos2019-blindness-detection' is found for 'APTOS2019' and
%   'messidor-2' for 'Messidor2'. See data/README.md for download notes.
if nargin >= 2 && ~isempty(root)
    return
end
bases = {};
env = getenv('NETRA_DATA');
if ~isempty(env)
    bases{end + 1} = env;
end
cfg = netra.config();
bases{end + 1} = fullfile(cfg.paths.root, 'data');
norm = @(s) lower(regexprep(s, '[^A-Za-z0-9]', ''));
key = norm(name);
aliases = struct('aptos2019', {{'aptos2019', 'aptos'}}, ...
    'idrid', {{'idrid', 'indiandiabeticretinopathy'}}, ...
    'drive', {{'drive'}}, ...
    'messidor2', {{'messidor2'}});
cands = {key};
if isfield(aliases, key)
    cands = aliases.(key);
end
for b = 1:numel(bases)
    if ~exist(bases{b}, 'dir')
        continue
    end
    d = dir(bases{b});
    d = d([d.isdir]);
    for k = 1:numel(d)
        n = norm(d(k).name);
        for c = 1:numel(cands)
            if strncmp(n, cands{c}, numel(cands{c}))
                root = fullfile(bases{b}, d(k).name);
                return
            end
        end
    end
end
root = fullfile(bases{end}, name);
end
