function m = readMask(file)
%READMASK Read a ground-truth mask (GIF, TIFF, PNG; indexed, grey or RGB) as logical.
%   Any non-zero pixel of a lossless mask is foreground: DRIVE stores 0/255
%   GIFs, IDRiD stores lesions as coloured TIFFs, other releases use 0/1
%   PNGs. Indexed images are resolved through their palette first.
[X, map] = imread(file);
if size(X, 3) == 4 || size(X, 3) == 2
    X = X(:, :, 1:end - 1);                  % drop an alpha channel
end
if ~isempty(map)
    try
        m = any(ind2rgb(X, map) > 0.5, 3);
    catch
        m = any(X > 0, 3);        % palette shorter than the stored values (some GIF writers)
    end
elseif islogical(X)
    m = any(X, 3);
else
    m = any(X > 0, 3);
end
end
