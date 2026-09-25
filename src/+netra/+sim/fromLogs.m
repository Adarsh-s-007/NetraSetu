function out = fromLogs(P, D, X, L)
%FROMLOGS Programme indicators and daily series from per-step signal logs.
%
%   out = netra.sim.fromLogs(P, D, X, L) turns the signals logged by a run
%   (netra.sim.runReference, the Simulink model or its block emulator; see
%   netra.sim.simulinkBlocks for the list) into out.kpi via netra.sim.kpis,
%   plus out.series (daily totals and end-of-day backlogs) and out.logs.

T = X.T;
secG = X.secondsPerCase(1);
secO = X.secondsPerCase(2);
tot = struct('arrivals', sum(L.nArrived), 'captured', sum(L.nCaptured), ...
    'balked', sum(L.nBalked));
work = struct('grader', sum(L.casesG) * secG / 3600, 'ophth', sum(L.casesO) * secO / 3600, ...
    'sent', sum(L.sent), 'graded', sum(L.graded));
backlog = struct('uplink', L.upBacklog(end), 'ai', L.aiBacklog(end), ...
    'review', L.reviewBacklog(end), 'audit', L.auditBacklog(end), ...
    'ophthalmologist', L.ophthBacklog(end));
out = netra.sim.kpis(P, D, X, L.H, tot, work, backlog);

stepsPerDay = round(24 / X.dt);
nDays = ceil(T * X.dt / 24);
day = floor((0:T - 1)' / stepsPerDay) + 1;
endOfDay = stepsPerDay:stepsPerDay:T;
ser = struct();
ser.captured = accumarray(day, L.nCaptured(:), [nDays 1]);
ser.balked = accumarray(day, L.nBalked(:), [nDays 1]);
ser.graderBusy = accumarray(day, L.casesG(:) * secG / 3600, [nDays 1]);
ser.uplinkBacklog = zeros(nDays, 1);
ser.reviewBacklog = zeros(nDays, 1);
ser.ophthBacklog = zeros(nDays, 1);
ser.uplinkBacklog(1:numel(endOfDay)) = L.upBacklog(endOfDay);
ser.reviewBacklog(1:numel(endOfDay)) = L.reviewBacklog(endOfDay);
ser.ophthBacklog(1:numel(endOfDay)) = L.ophthBacklog(endOfDay);
out.series = ser;
out.logs = L;
end
