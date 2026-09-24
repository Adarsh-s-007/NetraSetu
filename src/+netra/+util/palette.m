function P = palette()
%PALETTE NetraSetu colour system (RGB in [0, 1]).
%   The palette is built around the fundus itself: a deep "ink" for text,
%   the saffron of the programme mark, and lesion colours chosen so that
%   every class stays distinguishable on an orange-red retina and for the
%   common forms of colour-vision deficiency (red lesions are outlined, not
%   filled, and each class also differs in marker shape).
hex = @(h) [hex2dec(h(2:3)) hex2dec(h(4:5)) hex2dec(h(6:7))] / 255;
P = struct();
P.ink       = hex('#14182E');   % text, frames
P.inkSoft   = hex('#4A5070');
P.paper     = hex('#FBF8F3');   % report background (warm paper)
P.rule      = hex('#E4DED3');
P.saffron   = hex('#E8930C');   % brand accent
P.retina    = hex('#C4441C');
P.teal      = hex('#0F8A7E');
% lesion classes
P.ma        = hex('#FF3B5C');   % microaneurysm: bright crimson ring
P.dot       = hex('#FF7A90');
P.blot      = hex('#B83DBA');   % blot haemorrhage: violet contour
P.flame     = hex('#7B4DFF');
P.preret    = hex('#5B1A8C');
P.exudate   = hex('#FFD43B');   % hard exudate: yellow contour
P.cws       = hex('#9BE7FF');   % cotton-wool spot: ice blue
P.nv        = hex('#7CFC5A');   % neovascularisation: acid green box
P.vb        = hex('#FF9F1C');   % venous beading
P.irma      = hex('#36D6C3');
P.od        = hex('#FFFFFF');
P.fovea     = hex('#E0F2FF');
% triage
P.ROUTINE      = hex('#0F8A7E');
P.REFER        = hex('#E8930C');
P.URGENT       = hex('#D7263D');
P.HUMAN_REVIEW = hex('#3D4DB7');
P.RECAPTURE    = hex('#6B7280');
% ICDR scale 0..4
P.grades = [hex('#0F8A7E'); hex('#7FB069'); hex('#E8C547'); hex('#E8930C'); hex('#D7263D')];
end
