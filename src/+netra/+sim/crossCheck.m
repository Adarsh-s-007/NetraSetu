function C = crossCheck(a, b, tol)
%CROSSCHECK Compare two simulation runs signal by signal and KPI by KPI.
%
%   C = netra.sim.crossCheck(ref, other)          tolerance 1e-9 (relative)
%   C = netra.sim.crossCheck(ref, other, tol)
%   netra.sim.crossCheck(ref, other)              prints the comparison
%
%   ref and other are outputs of netra.sim.runReference and
%   netra.sim.runSimulink (Simulink or its block emulator). Every logged
%   signal is compared at every step, the turnaround histograms H bin by
%   bin, and every numeric KPI. Differences are relative to the magnitude
%   of the reference (floored at 1 patient / 1 hour / 1 rupee).
%   C.pass, C.maxRelative, C.worst (name of the worst quantity),
%   C.signals and C.kpis (name, reference, other, relative difference).

if nargin < 3
    tol = 1e-9;
end
C = struct('signals', struct('name', {}, 'ref', {}, 'other', {}, 'rel', {}), ...
    'kpis', struct('name', {}, 'ref', {}, 'other', {}, 'rel', {}));
f = fieldnames(a.logs);
for i = 1:numel(f)
    x = a.logs.(f{i});
    y = b.logs.(f{i});
    if ~isequal(size(x), size(y))
        rel = Inf;
    else
        rel = max(abs(x(:) - y(:))) / max(1, max(abs(x(:))));
    end
    C.signals(end + 1) = struct('name', f{i}, 'ref', sum(x(:)), 'other', sum(y(:)), 'rel', rel);
end
[na, va] = flatten(a.kpi, 'kpi');
[nb, vb] = flatten(b.kpi, 'kpi');
for i = 1:numel(na)
    j = find(strcmp(nb, na{i}), 1);
    if isempty(j)
        rel = Inf;
        other = NaN;
    else
        other = vb(j);
        rel = abs(va(i) - other) / max(1, abs(va(i)));
    end
    C.kpis(end + 1) = struct('name', na{i}, 'ref', va(i), 'other', other, 'rel', rel);
end
all_ = [C.signals, C.kpis];
[C.maxRelative, w] = max([all_.rel]);
C.worst = all_(w).name;
C.tolerance = tol;
C.pass = C.maxRelative <= tol;
if nargout == 0
    fprintf('\n  %-34s %16s %16s %10s\n', 'quantity', 'reference', 'other', 'rel.diff');
    for i = 1:numel(C.signals)
        s = C.signals(i);
        fprintf('  %-34s %16.6g %16.6g %10.1e\n', ['sum ' s.name], s.ref, s.other, s.rel);
    end
    keyK = {'kpi.screened', 'kpi.turnaround.routineP95', 'kpi.turnaround.urgentP95', ...
        'kpi.utilisation.graders', 'kpi.utilisation.ophthalmologist', ...
        'kpi.reachingTreatment', 'kpi.cost.total'};
    for i = 1:numel(keyK)
        j = find(strcmp({C.kpis.name}, keyK{i}), 1);
        if ~isempty(j)
            s = C.kpis(j);
            fprintf('  %-34s %16.6g %16.6g %10.1e\n', s.name, s.ref, s.other, s.rel);
        end
    end
    verdict = 'MATCH';
    if ~C.pass
        verdict = 'MISMATCH';
    end
    fprintf('  %s: %d signals and %d KPIs, largest relative difference %.2g (%s)\n\n', ...
        verdict, numel(C.signals), numel(C.kpis), C.maxRelative, C.worst);
    clear C
end
end

% ======================================================================
function [names, vals] = flatten(s, prefix)
names = {};
vals = [];
f = fieldnames(s);
for i = 1:numel(f)
    v = s.(f{i});
    n = [prefix '.' f{i}];
    if isstruct(v) && isscalar(v)
        [nn, vv] = flatten(v, n);
        names = [names, nn]; %#ok<AGROW>
        vals = [vals, vv]; %#ok<AGROW>
    elseif (isnumeric(v) || islogical(v)) && isscalar(v)
        names{end + 1} = n; %#ok<AGROW>
        vals(end + 1) = double(v); %#ok<AGROW>
    end
end
end
