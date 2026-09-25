function name = variantName(key, fullKey)
%VARIANTNAME Readable name of a branch combination ('cnn_lesion' -> 'CNN + lesion ensemble').
%   name = netra.eval.variantName(key, fullKey) - the deployed combination
%   (fullKey) is called the integrated pipeline.
parts = strsplit(key, '_');
nice = struct('cnn', 'CNN', 'lesion', 'lesion ensemble', 'rules', 'rule engine');
words = cellfun(@(p) nice.(p), parts, 'UniformOutput', false);
if nargin >= 2 && strcmp(key, fullKey)
    if numel(parts) > 1
        name = 'Integrated pipeline';
    else
        name = sprintf('Integrated pipeline (%s)', words{1});
    end
    return
end
name = strjoin(words, ' + ');
if numel(parts) == 1
    name = [upper(name(1)) name(2:end) ' only'];
else
    name(1) = upper(name(1));
end
end
