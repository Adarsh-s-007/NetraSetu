function b = textBox(h)
%TEXTBOX Bounding box [x0 y0 x1 y1] of a text object, as it will be drawn.
%   GNU Octave measures text 'Extent' at 72 pixels per inch but renders
%   (and prints) at the screen's resolution, so on a 96-100 ppi display the
%   drawn text is ~1.35x larger than its measured extent. The box is scaled
%   about the text's anchor accordingly; MATLAB's extent is used as is.
e = get(h, 'Extent');
b = [e(1), e(2), e(1) + e(3), e(2) + e(4)];
if ~netra.util.isOctave()
    return
end
k = get(0, 'ScreenPixelsPerInch') / 72;
if k <= 1
    return
end
w = e(3) * k;
v = e(4) * k;
switch get(h, 'HorizontalAlignment')
    case 'right'
        x0 = b(3) - w;
    case 'center'
        x0 = (b(1) + b(3)) / 2 - w / 2;
    otherwise
        x0 = b(1);
end
switch get(h, 'VerticalAlignment')
    case {'top', 'cap'}
        y0 = b(4) - v;
    case 'middle'
        y0 = (b(2) + b(4)) / 2 - v / 2;
    otherwise
        y0 = b(2);
end
b = [x0, y0, x0 + w, y0 + v];
end
