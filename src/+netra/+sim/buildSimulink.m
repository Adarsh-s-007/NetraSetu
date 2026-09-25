function model = buildSimulink(model, varargin)
%BUILDSIMULINK Build the NetraSetu district tele-screening model in Simulink.
%
%   netra.sim.buildSimulink()                         'NetraSetuTelescreening'
%   netra.sim.buildSimulink(name, 'Folder', f, 'Open', true, 'Save', true)
%
%   Draws the model described by netra.sim.simulinkBlocks: a discrete,
%   fixed-step (nsim.dt hours) flow model of a district programme with
%   one MATLAB Function block per stage
%
%     From Workspace: arrivals, capture capacity, link-limited upload
%     capacity (Markov outages x upload windows), grader and
%     ophthalmologist rosters
%       -> 1 Capture -> 2 Route (edge AI) -> 3 Uplink -> 4 Grade
%       -> 5 Review -> 6 Ophthalmologist -> 7 Results
%       -> To Workspace logs, Scopes
%
%   Each block calls the netra.sim.stage* function the MATLAB reference
%   simulator calls and keeps its queues (sites x hours since capture) as
%   persistent state. Wiring is by signal name. Parameters and inputs are
%   read from the variable 'nsim' (netra.sim.simulinkInputs), which
%   netra.sim.runSimulink supplies through a Simulink.SimulationInput; the
%   model's InitFcn creates a default 'nsim' when the model is run from the
%   toolstrip. Requires Simulink and a C compiler supported for MATLAB
%   Function blocks.

if nargin < 1 || isempty(model)
    model = 'NetraSetuTelescreening';
end
o = netra.util.opts(struct('Folder', pwd, 'Open', false, 'Save', true), varargin{:});
if netra.util.isOctave() || ~netra.util.has('new_system')
    error('netra:sim:simulink', 'Building the model requires Simulink.');
end
M = netra.sim.simulinkBlocks();
if bdIsLoaded(model)
    close_system(model, 0);
end
new_system(model);
load_system(model);
set_param(model, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
    'FixedStep', 'nsim.dt', 'StartTime', '0', 'StopTime', 'nsim.stopTime', ...
    'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SaveFinalState', 'off', ...
    'SignalLogging', 'off', 'ReturnWorkspaceOutputs', 'on');
set_param(model, 'InitFcn', sprintf(['%% default inputs when the model is run on its own\n' ...
    'if ~exist(''nsim'', ''var'')\n    nsim = netra.sim.simulinkInputs();\nend']));

% ------------------------------------------------------------- layout
nb = numel(M.blocks);
pitch = 460;
top = 300;
w = 180;
h = zeros(1, nb);
x = zeros(1, nb);
for b = 1:nb
    h(b) = max(80, 30 * max(numel(M.blocks(b).in), numel(M.blocks(b).out)) + 20);
    x(b) = 420 + (b - 1) * pitch;
end
bottom = top + max(h);
producer = containers.Map();           % signal -> [block port]
for b = 1:nb
    for j = 1:numel(M.blocks(b).out)
        producer(M.blocks(b).out{j}) = [b j];
    end
end
srcIdx = containers.Map({M.sources.name}, num2cell(1:numel(M.sources)));
consumers = containers.Map();
for b = 1:nb
    for j = 1:numel(M.blocks(b).in)
        n = M.blocks(b).in{j};
        if consumers.isKey(n)
            consumers(n) = consumers(n) + 1;
        else
            consumers(n) = 1;
        end
    end
end

% ------------------------------------------------------ stage blocks
for b = 1:nb
    B = M.blocks(b);
    path = [model '/' B.name];
    add_block('simulink/User-Defined Functions/MATLAB Function', path, ...
        'Position', [x(b) top x(b) + w top + h(b)]);
    code = sprintf('function [%s] = %s(%s)\n%s\n', strjoin(B.out, ', '), lower(B.name), ...
        strjoin(B.in, ', '), strjoin(B.code', sprintf('\n')));
    setScript(path, code);
    set_param(path, 'BackgroundColor', B.color);
    note(model, [x(b) top - 44 x(b) + w + 60 top - 12], B.label, 11, 'bold');
end

% --------------------------------------- sources, feeding each stage
for b = 1:nb
    B = M.blocks(b);
    nAbove = 0;
    nBelow = 0;
    for j = 1:numel(B.in)
        n = B.in{j};
        if ~srcIdx.isKey(n)
            continue
        end
        s = M.sources(srcIdx(n));
        name = n;
        if consumers(n) > 1
            name = sprintf('%s for %s', n, B.name);
        end
        path = [model '/' name];
        if strcmp(s.kind, 'series')
            nAbove = nAbove + 1;
            y0 = top - 20 - 62 * nAbove;
            add_block('simulink/Sources/From Workspace', path, ...
                'Position', [x(b) - 150 y0 x(b) - 30 y0 + 32]);
            set_param(path, 'VariableName', s.value, 'Interpolate', 'off', ...
                'OutputAfterFinalValue', 'Holding final value', 'SampleTime', 'nsim.dt', ...
                'ZeroCross', 'off');
        else
            y0 = bottom + 40 + 50 * nBelow;
            nBelow = nBelow + 1;
            add_block('simulink/Sources/Constant', path, ...
                'Position', [x(b) - 140 y0 x(b) - 30 y0 + 30]);
            set_param(path, 'Value', s.value, 'VectorParams1D', 'off');
        end
        link(model, name, 1, B.name, j, n);
    end
end

% --------------------------------------------- stage-to-stage signals
for b = 1:nb
    B = M.blocks(b);
    for j = 1:numel(B.in)
        n = B.in{j};
        if producer.isKey(n)
            pp = producer(n);
            link(model, M.blocks(pp(1)).name, pp(2), B.name, j, n);
        end
    end
end

% ------------------------------------------------- logs and terminators
nLog = zeros(1, nb);
for b = 1:nb
    B = M.blocks(b);
    for j = 1:numel(B.out)
        n = B.out{j};
        g = find(strcmp({M.logs.signal}, n), 1);
        if ~isempty(g)
            y0 = bottom + 40 + 45 * nLog(b);
            nLog(b) = nLog(b) + 1;
            path = [model '/ns_' n];
            add_block('simulink/Sinks/To Workspace', path, ...
                'Position', [x(b) + w + 25 y0 x(b) + w + 125 y0 + 28]);
            maxPts = 'inf';
            if strcmp(M.logs(g).mode, 'last')
                maxPts = '1';
            end
            set_param(path, 'VariableName', ['ns_' n], 'SaveFormat', 'Array', ...
                'MaxDataPoints', maxPts, 'SampleTime', '-1');
            link(model, B.name, j, ['ns_' n], 1, n);
        elseif ~consumed(M, n)
            path = [model '/unused ' n];
            add_block('simulink/Sinks/Terminator', path, ...
                'Position', [x(b) + w + 30 top + 30 * j - 10 x(b) + w + 50 top + 30 * j + 10]);
            link(model, B.name, j, ['unused ' n], 1, n);
        end
    end
end

% ------------------------------------------------------------- scopes
for k = 1:numel(M.scopes)
    sc = M.scopes(k);
    pp = producer(sc.signals{1});
    b = pp(1);
    y0 = bottom + 60 + 45 * nLog(b);
    nLog(b) = nLog(b) + 2;
    path = [model '/' sc.name];
    add_block('simulink/Sinks/Scope', path, ...
        'Position', [x(b) + w + 25 y0 x(b) + w + 85 y0 + 40 + 10 * numel(sc.signals)]);
    set_param(path, 'NumInputPorts', num2str(numel(sc.signals)));
    for j = 1:numel(sc.signals)
        q = producer(sc.signals{j});
        link(model, M.blocks(q(1)).name, q(2), sc.name, j, sc.signals{j});
    end
end

% -------------------------------------------------------- annotations
note(model, [x(1) - 160 30 x(1) + 900 60], M.title, 16, 'bold');
note(model, [x(1) - 160 64 x(1) + 1600 84], M.note, 11, 'normal');

if o.Save
    if ~exist(o.Folder, 'dir')
        mkdir(o.Folder);
    end
    save_system(model, fullfile(o.Folder, [model '.slx']));
end
if o.Open
    open_system(model);
end
end

% ======================================================================
function link(model, src, sp, dst, dp, name)
lh = add_line(model, sprintf('%s/%d', src, sp), sprintf('%s/%d', dst, dp), ...
    'autorouting', 'on');
try
    set_param(lh, 'Name', name);
catch
end
end

function tf = consumed(M, n)
tf = false;
for b = 1:numel(M.blocks)
    if any(strcmp(M.blocks(b).in, n))
        tf = true;
        return
    end
end
end

function setScript(blk, code)
% MATLAB Function block code: MATLABFunctionConfiguration (R2019b+), else
% the Stateflow API (no Stateflow licence needed for MATLAB Function blocks)
try
    cfgObj = get_param(blk, 'MATLABFunctionConfiguration');
    cfgObj.FunctionScript = code;
    return
catch
end
rt = sfroot;
ch = rt.find('-isa', 'Stateflow.EMChart', 'Path', blk);
ch.Script = code;
end

function note(model, pos, text, fontSize, weight)
try
    a = Simulink.Annotation(model, text);
catch
    try
        a = Simulink.Annotation([model '/' strrep(text, '/', '//')]);
    catch
        return
    end
end
try
    a.Position = pos;
    a.FontSize = fontSize;
    a.FontWeight = weight;
    a.HorizontalAlignment = 'left';
catch
end
end
