function out = runReference(P, D, S)
%RUNREFERENCE Simulate one year of a district tele-screening programme.
%
%   out = netra.sim.runReference(P)            defaults, P.decision, new scenario
%   out = netra.sim.runReference(P, D, S)      decision struct D, scenario S
%
%   D (see netra.sim.defaults, P.decision):
%     phcEquipped  PHCs with a camera and trained technician (first n)
%     vans         mobile screening units
%     linkTier     0 = today's mix, k = upgrade every PHC to at least tier k
%                  (1 2G, 2 3G, 3 4G, 4 fibre)
%     aiMode       'edge' (grading on the PHC laptop, only flagged eyes are
%                  uploaded) or 'cloud' (every image is uploaded)
%     graders      optometrist graders at the reading hub
%     ophthHours   ophthalmologist tele-reading hours per weekday
%     sensitivity  AI operating point for auto-clearing
%     reviewMode   'xai' (NetraSetu console, 30 s) or 'plain' (150 s)
%
%   One step per hour, patient cohorts tracked by age since capture:
%     capture -> route (edge AI grades on the spot) -> store-and-forward
%     uplink (per site, Markov link outages, upload windows) -> central
%     grading (cloud mode) -> grader review (urgent > routine > audit) ->
%     ophthalmologist adjudication -> results
%   Urgent referrals leave after grader confirmation (the ophthalmologist
%   adjudicates in parallel); with edge AI and P.referral.provisionalOnSite
%   the patient is counselled at the PHC the moment the eye is flagged.
%
%   The loop calls netra.sim.stage* - the same functions the Simulink
%   model's MATLAB Function blocks call - on inputs from netra.sim.prepare,
%   logs the same per-step signals, and turns them into indicators with
%   the same netra.sim.fromLogs, so the two can be compared step by step
%   (netra.sim.crossCheck).
%
%   out.kpi: screened, demand, unserved, turnaround quantiles per path
%   (hours), utilisation of every resource, programme sensitivity,
%   referable eyes found, patients reaching treatment, annual cost (INR),
%   cost per screen, constraint margins. out.series: daily time series.
%   out.logs: per-step signals (see netra.sim.simulinkBlocks).

if nargin < 2 || isempty(D)
    D = P.decision;
end
if ~isfield(D, 'reviewMode')
    D.reviewMode = P.decision.reviewMode;
end
if nargin < 3 || isempty(S)
    S = netra.sim.scenario(P);
end
X = netra.sim.prepare(P, D, S);
T = X.T;
p = X.p;

wait = X.x0.wait;
qUp = X.x0.qUp;
qAI = X.x0.q1; qU = X.x0.q1; qR = X.x0.q1; qQ = X.x0.q1; qOU = X.x0.q1; qOR = X.x0.q1;
H = X.x0.H;
z = zeros(T, 1);
L = struct('nArrived', z, 'nCaptured', z, 'nBalked', z, 'waiting', z, 'sent', z, ...
    'upBacklog', z, 'graded', z, 'aiBacklog', z, 'casesG', z, 'reviewBacklog', z, ...
    'auditBacklog', z, 'casesO', z, 'ophthBacklog', z, 'H', []);

for k = 1:T
    [wait, captured, balked] = netra.sim.stepCapture(wait, X.arrivals(k, :)', ...
        X.capCapture(k, :)', X.closing(k, :)');
    [toUp, autoNow] = netra.sim.stageRoute(captured, p);
    [qUp, arrived, sent] = netra.sim.stageUplink(qUp, toUp, X.upCap(k, :)');
    [qAI, inU, inR, inQ, autoByAge, graded] = netra.sim.stageGrade(qAI, arrived, p);
    [qU, qR, qQ, doneU, doneR, ~, nG] = netra.sim.stageReview(qU, qR, qQ, inU, inR, inQ, ...
        X.graderCap(k));
    [qOU, qOR, doneOU, doneOR, nO] = netra.sim.stageOphth(qOU, qOR, doneU, doneR, X.ophthCap(k), p);
    H = netra.sim.stageTally(H, autoNow, autoByAge, doneU, doneR, doneOU, doneOR, p);

    % the signals the Simulink model logs, computed the same way
    L.nArrived(k) = sum(X.arrivals(k, :));
    L.nCaptured(k) = sum(captured);
    L.nBalked(k) = sum(balked);
    L.waiting(k) = sum(wait);
    L.sent(k) = sent;
    L.upBacklog(k) = sum(qUp(:));
    L.graded(k) = graded;
    L.aiBacklog(k) = sum(qAI);
    L.casesG(k) = nG;
    L.reviewBacklog(k) = sum(qU) + sum(qR);
    L.auditBacklog(k) = sum(qQ);
    L.casesO(k) = nO;
    L.ophthBacklog(k) = sum(qOU) + sum(qOR);
end
L.H = H;
out = netra.sim.fromLogs(P, D, X, L);
end
