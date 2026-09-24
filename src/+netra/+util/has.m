function tf = has(name)
%HAS True if a function, class or Simulink/toolbox entry point is callable.
%   Results are cached per session. Under GNU Octave, MATLAB-only features
%   (deep learning, ensembles, Simulink, uifigure) report false.
persistent cache
if isempty(cache)
    cache = containers.Map();
end
if isKey(cache, name)
    tf = cache(name);
    return
end
tf = exist(name) > 0; %#ok<EXIST>
if netra.util.isOctave() && any(strcmp(name, {'imnlmfilt', 'dlnetwork', 'trainnet', ...
        'fitcensemble', 'bayesopt', 'new_system', 'uifigure', 'exportgraphics', 'shapley'}))
    tf = false;
end
cache(name) = tf;
end
