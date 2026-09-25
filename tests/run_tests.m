function summary = run_tests(filter)
%RUN_TESTS Run NetraSetu's script-based tests in MATLAB or GNU Octave.
%
%   run_tests                 run every tests/test_*.m
%   run_tests('quality')      run files whose name contains 'quality'
%   s = run_tests(...)        struct array: file, name, passed, message, seconds
%
%   Each test file is a script. Code before the first %% line is shared
%   setup; every %% section is an independent test case that sees only the
%   setup variables. This is exactly MATLAB's script-based test convention,
%   so in MATLAB the same files also run with runtests('tests').

if nargin < 1
    filter = '';
end
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(root);
netrasetu_setup('quiet');

files = dir(fullfile(here, 'test_*.m'));
if ~isempty(filter)
    files = files(~cellfun(@isempty, strfind({files.name}, filter)));
end

summary = struct('file', {}, 'name', {}, 'passed', {}, 'message', {}, 'seconds', {});
fprintf('\nNetraSetu test suite (%d files)\n', numel(files));
fprintf('%s\n', repmat('-', 1, 72));
for f = 1:numel(files)
    [pre, names, bodies] = splitSections(fullfile(here, files(f).name));
    fprintf('%s\n', files(f).name);
    for s = 1:numel(bodies)
        t0 = tic;
        [ok, msg] = runIsolated([pre, sprintf('\n'), bodies{s}]); %#ok<SPRINTFN>
        dt = toc(t0);
        summary(end + 1) = struct('file', files(f).name, 'name', names{s}, ... %#ok<AGROW>
            'passed', ok, 'message', msg, 'seconds', dt);
        if ok
            fprintf('  PASS  %-52s %6.2fs\n', names{s}, dt);
        else
            fprintf('  FAIL  %-52s %6.2fs\n        %s\n', names{s}, dt, msg);
        end
    end
end
nPass = nnz([summary.passed]);
fprintf('%s\n%d / %d passed\n\n', repmat('-', 1, 72), nPass, numel(summary));
end

function [pre, names, bodies] = splitSections(file)
txt = fileread(file);
lines = regexp(txt, '\r?\n', 'split');
isHead = ~cellfun(@isempty, regexp(lines, '^\s*%%', 'once'));
heads = find(isHead);
if isempty(heads)
    pre = '';
    names = {'(script)'};
    bodies = {txt};
    return
end
pre = strjoin(lines(1:heads(1) - 1), sprintf('\n')); %#ok<SPRINTFN>
names = cell(1, numel(heads));
bodies = cell(1, numel(heads));
for k = 1:numel(heads)
    last = numel(lines);
    if k < numel(heads)
        last = heads(k + 1) - 1;
    end
    names{k} = strtrim(regexprep(lines{heads(k)}, '^\s*%%\s*', ''));
    bodies{k} = strjoin(lines(heads(k) + 1:last), sprintf('\n')); %#ok<SPRINTFN>
end
end

function [netraOk__, netraMsg__] = runIsolated(netraCode__)
% Variable names are decorated so that test code cannot shadow them.
netraOk__ = true;
netraMsg__ = '';
try
    eval(netraCode__);
catch netraErr__
    netraOk__ = false;
    netraMsg__ = netraErr__.message;
    if ~isempty(netraErr__.stack)
        netraMsg__ = sprintf('%s  (%s:%d)', netraMsg__, netraErr__.stack(1).name, ...
            netraErr__.stack(1).line);
    end
end
end
