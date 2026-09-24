function tf = isOctave()
%ISOCTAVE True when running under GNU Octave (repository CI), false in MATLAB.
persistent cached
if isempty(cached)
    cached = exist('OCTAVE_VERSION', 'builtin') > 0;
end
tf = cached;
end
