function I = toRGB(I)
%TORGB Convert any readable image to a double RGB array in [0, 1].
%   Handles uint8/uint16/logical/single inputs, grey-level images (replicated
%   to three channels) and RGBA captures (alpha dropped).
if islogical(I)
    I = double(I);
elseif isinteger(I)
    I = double(I) / double(intmax(class(I)));
else
    I = double(I);
    if max(I(:)) > 1.5          % 0..255 stored as double
        I = I / 255;
    end
end
if size(I, 3) == 1
    I = repmat(I, [1 1 3]);
elseif size(I, 3) > 3
    I = I(:, :, 1:3);
end
I = min(max(I, 0), 1);
end
