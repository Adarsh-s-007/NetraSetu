function M = montage(tiles, nCols, gap, bg)
%MONTAGE Tile images (cell array, grey or RGB, any size) into one RGB image.
%   M = netra.util.montage(tiles, nCols, gap, bg) - every tile is scaled to
%   the height of the first one; gap in pixels (default 8), bg RGB in [0,1]
%   (default the report paper colour). Toolbox-free, for experiment figures.
if nargin < 2 || isempty(nCols)
    nCols = numel(tiles);
end
if nargin < 3 || isempty(gap)
    gap = 8;
end
if nargin < 4 || isempty(bg)
    bg = [251 248 243] / 255;
end
h = size(tiles{1}, 1);
for k = 1:numel(tiles)
    t = tiles{k};
    if isinteger(t)
        t = double(t) / double(intmax(class(t)));    % scale by type, never by content
    else
        t = double(t);                               % floating point: [0, 1] (clipped below)
    end
    if size(t, 3) == 1
        t = repmat(t, [1 1 3]);
    end
    if size(t, 1) ~= h
        t = netra.util.imscale(t, h / size(t, 1));
        t = t(1:min(h, size(t, 1)), :, :);
        if size(t, 1) < h
            t(end + 1:h, :, :) = 0;
        end
    end
    tiles{k} = min(max(t, 0), 1);
end
w = max(cellfun(@(t) size(t, 2), tiles));
nRows = ceil(numel(tiles) / nCols);
M = repmat(reshape(bg, 1, 1, 3), [nRows * (h + gap) + gap, nCols * (w + gap) + gap, 1]);
for k = 1:numel(tiles)
    r = floor((k - 1) / nCols);
    c = mod(k - 1, nCols);
    y0 = gap + r * (h + gap);
    x0 = gap + c * (w + gap);
    t = tiles{k};
    M(y0 + (1:size(t, 1)), x0 + (1:size(t, 2)), :) = t;
end
end
