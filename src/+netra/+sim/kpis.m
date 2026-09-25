function out = kpis(P, D, X, H, tot, work, backlog)
%KPIS Programme indicators from the result histograms of a simulation run.
%
%   out = netra.sim.kpis(P, D, X, H, tot, work, backlog) is shared by the
%   MATLAB reference (netra.sim.runReference) and the Simulink model
%   (netra.sim.runSimulink): H (4 x B) holds completed results by age since
%   capture for 1 AI-cleared, 2 routine referrals, 3 urgent referrals, 4
%   urgent cases confirmed by the ophthalmologist; tot the arrivals,
%   captured and balked counts; work the grader / ophthalmologist hours
%   used, uploads and central gradings; backlog what is still queued.

dt = X.dt;
B = X.B;
ages = ((1:B) - 0.5) * dt;
q = @(h, pct) histQuantile(h, ages, pct);
edge = X.p(1) > 0.5;
fr = X.fractions;
K = struct();
K.demand = tot.arrivals;
K.screened = tot.captured;
K.unserved = tot.balked;
K.flagged = sum(H(2, :)) + sum(H(3, :));
K.autoCleared = sum(H(1, :));
K.turnaround = struct( ...
    'autoP50', q(H(1, :), 0.5), 'autoP95', q(H(1, :), 0.95), ...
    'routineP50', q(H(2, :), 0.5), 'routineP95', q(H(2, :), 0.95), ...
    'urgentP50', q(H(3, :), 0.5), 'urgentP95', q(H(3, :), 0.95), ...
    'urgentConfirmedP95', q(H(4, :), 0.95));
% time until the patient is TOLD to go to hospital: with edge AI and
% on-site counselling this is the moment of capture for AI-urgent eyes
K.urgentNoticeP95 = K.turnaround.urgentP95;
if edge && P.referral.provisionalOnSite
    K.urgentNoticeP95 = P.ai.edgeSecondsPerPatient / 3600;
end
K.utilisation = struct( ...
    'graders', work.grader / max(sum(X.graderHours), eps), ...
    'ophthalmologist', work.ophth / max(sum(X.ophthHours), eps), ...
    'uplink', work.sent / max(sum(X.upCap(:)), eps));
K.backlogEnd = backlog;
K.aiSensitivity = X.se;
K.aiSpecificity = X.sp;
K.programmeSensitivity = X.se + (1 - X.se) * P.review.qaShare;
pi_ = P.mix.referable;
K.referableFound = K.screened * fr.gradable * pi_ * K.programmeSensitivity;
K.missedReferable = K.screened * fr.gradable * pi_ * (1 - K.programmeSensitivity);
% patients who act on a referral: counselled on site (edge AI flags the eye
% while the patient is still at the PHC) or informed after the review
uOn = P.referral.uptakeOnSite;
uLate = P.referral.uptakeDelayed;
if edge && P.referral.provisionalOnSite
    uptakeU = uOn;
    uptakeR = uOn;
else
    w = uLate + (uOn - uLate) * exp(-ages / P.referral.presenceHours);
    uptakeU = sum(H(3, :) .* w) / max(sum(H(3, :)), eps);
    uptakeR = sum(H(2, :) .* w) / max(sum(H(2, :)), eps);
end
K.reachingTreatment = sum(H(3, :)) * uptakeU + sum(H(2, :)) * fr.refInRoutine * uptakeR;
% annualise when a shorter horizon is simulated (the optimiser uses 26 weeks)
f = 364 / P.days;
K.perYear = struct('screened', f * K.screened, 'referableFound', f * K.referableFound, ...
    'missedReferable', f * K.missedReferable, 'reachingTreatment', f * K.reachingTreatment, ...
    'unserved', f * K.unserved);
K.cost = costOf(P, D, X, K, f);
K.costPerScreen = K.cost.total / max(K.perYear.screened, 1);
K.constraints = struct( ...
    'screens', K.perYear.screened - P.target.screensPerYear, ...
    'routineP95', P.target.routineP95Hours - K.turnaround.routineP95, ...
    'urgentP95', P.target.urgentP95Hours - K.urgentNoticeP95, ...
    'graderLoad', P.target.maxUtilisation - K.utilisation.graders, ...
    'ophthLoad', P.target.maxUtilisation - K.utilisation.ophthalmologist, ...
    'sensitivity', K.programmeSensitivity - P.target.programmeSensitivity);
c = struct2cell(K.constraints);
K.feasible = all([c{:}] >= 0);
hist = struct('auto', H(1, :), 'routine', H(2, :), 'urgent', H(3, :), 'urgentConfirmed', H(4, :));
out = struct('kpi', K, 'hist', hist, 'H', H, 'ages', ages, 'decision', D, 'fractions', fr);
end

% ======================================================================
function v = histQuantile(h, ages, pct)
s = sum(h);
if s <= 0
    v = 0;
    return
end
c = cumsum(h) / s;
i = find(c >= pct, 1, 'first');
v = ages(i);
end

function C = costOf(P, D, X, K, f)
c = P.cost;
nPHC = nnz(X.active & ~X.isVan);
nVan = nnz(X.active & X.isVan);
cams = nPHC * P.capture.camerasPerPHC + 2 * nVan;
C = struct();
C.cameras = cams * (c.camera / c.cameraLife + c.camera * c.cameraUpkeep);
C.technicians = nPHC * c.technicianPerSite;
phcTier = X.tier(X.active & ~X.isVan);
C.links = sum(c.linkPerSite(phcTier)) + sum(c.linkUpgradeOnce(phcTier)) / 5;
if strcmpi(D.aiMode, 'edge')
    C.ai = (nPHC + nVan) * c.edgeDevice / c.edgeLife;
else
    C.ai = c.cloudFixed + c.cloudPerPatient * K.screened * f;
end
C.graders = D.graders * c.graderFTE;
C.ophthalmologist = D.ophthHours * 250 * c.ophthPerHour;
C.vans = nVan * c.van;
names = fieldnames(C);
total = 0;
for k = 1:numel(names)
    total = total + C.(names{k});
end
C.total = total;
end
