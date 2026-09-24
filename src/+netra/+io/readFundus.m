function rgb = readFundus(file)
%READFUNDUS Read a fundus photograph of any common format as double RGB [0,1].
%   Handles JPEG/PNG/TIFF (8 or 16 bit), grey-level and RGBA files, and
%   multi-page TIFFs (first page).
if ~exist(file, 'file')
    error('netra:io:missing', 'File not found: %s', file);
end
[~, ~, ext] = fileparts(file);
if any(strcmpi(ext, {'.tif', '.tiff'}))
    img = imread(file, 1);
else
    img = imread(file);
end
rgb = netra.util.toRGB(img);
end
