function X = prepare(P, D, S)
%PREPARE Everything a simulation run needs that does not depend on its state.
%
%   X = netra.sim.prepare(P, D, S) applies the decision D to the scenario S:
%   which sites are active, their capture capacity, their link tier and the
%   resulting on/off link chain, upload windows, grader and ophthalmologist
%   capacity per hour, and the triage fractions implied by the AI operating
%   point. Both netra.sim.runReference and the Simulink model read exactly
%   these arrays (the model through From Workspace blocks), so the two
%   implementations cannot diverge in their inputs.
%
%   X fields: T, N, B, dt, arrivals, capCapture, closing, upCap (T x N);
%   graderCap, ophthCap, graderHours, ophthHours (T x 1); p (1 x 7 stage
%   parameters); x0 (initial states); fractions, se, sp, tier, active.

dt = P.dt;
B = round(P.maxAgeHours / dt);
T = S.T;
Np = S.nPHC;
N = Np + S.nVanMax;
active = [(1:Np) <= D.phcEquipped, (1:S.nVanMax) <= D.vans];
isVan = [false(1, Np), true(1, S.nVanMax)];

% links: tier, availability and a two-state Markov chain per site
tier = [S.tierOfSite(:)', 4 * ones(1, S.nVanMax)];
if D.linkTier > 0
    tier(1:Np) = max(tier(1:Np), D.linkTier);
end
A = P.link.availability(tier);
pRepair = min(1, dt ./ P.link.meanOutageHours(tier));
pFail = min(1, pRepair .* (1 - A) ./ max(A, eps));
up = true(1, N);
linkUp = false(T, N);
for k = 1:T
    u = S.linkU(k, :);
    up = (up & u >= pFail) | (~up & u < pRepair);
    linkUp(k, :) = up;
end
window = repmat(S.phcUpload(:), 1, N) .* repmat(~isVan, T, 1) + ...
         repmat(S.vanUpload(:), 1, N) .* repmat(isVan, T, 1);
perStep = P.link.mbps(tier) * P.link.efficiency * 3600 * dt / 8 / P.images.mbPerPatient;
upCap = double(linkUp) .* window .* repmat(perStep .* active, T, 1);

% capture
mins = P.capture.minutesPerPatient + P.capture.ungradableFirst * P.capture.recaptureMinutes;
cams = P.capture.camerasPerPHC * ~isVan + 2 * isVan;
capCapture = double(S.open) .* repmat(cams * 60 * dt / mins .* active, T, 1);

% reviewers
sec = P.review.secondsPerCase.(D.reviewMode);
secO = P.review.ophthSecondsPerCase.(D.reviewMode);
graderHours = D.graders * S.graderOn(:) * dt;
ophthHours = zeros(T, 1);
used = 0;
for k = 1:T
    if S.hourOfDay(k) < dt
        used = 0;
    end
    h = S.ophthOn(k) * min(dt, max(D.ophthHours - used, 0));
    ophthHours(k) = h;
    used = used + h;
end

% triage fractions from the operating point
[se, sp] = netra.sim.operatingCurve(P, D.sensitivity);
pi_ = P.mix.referable;
piU = P.mix.urgent;
ung = P.capture.ungradableFirst * (1 - P.capture.recaptureSuccess);
g = 1 - ung;
seU = max(P.ai.urgentSensitivity, se);
fUrgent = g * piU * seU;
tpRoutine = g * max(pi_ * se - piU * seU, 0);
fp = g * (1 - pi_) * (1 - sp);
unc = g * P.ai.uncertainShare * ((1 - pi_) * sp + pi_ * (1 - se));
fRoutine = tpRoutine + fp + unc + ung;
fAuto = max(1 - fUrgent - fRoutine, 0);
fQA = P.review.qaShare * fAuto;
edge = strcmpi(D.aiMode, 'edge');

X = struct();
X.T = T; X.N = N; X.B = B; X.dt = dt;
X.arrivals = S.arrivals .* repmat(active, T, 1);
X.capCapture = capCapture;
X.closing = double(S.closing) .* repmat(active, T, 1);
X.upCap = upCap;
X.linkUp = linkUp;
X.graderCap = graderHours * 3600 / sec;
X.ophthCap = ophthHours * 3600 / secO;
X.graderHours = graderHours;
X.ophthHours = ophthHours;
X.secondsPerCase = [sec secO];
X.p = [double(edge), fUrgent, fRoutine, fAuto, fQA, P.ai.cloudPatientsPerHour * dt, ...
    P.review.adjudicate];
X.x0 = struct('wait', zeros(N, 1), 'qUp', zeros(N, B), 'q1', zeros(1, B), 'H', zeros(4, B));
X.fractions = struct('urgent', fUrgent, 'routine', fRoutine, 'auto', fAuto, 'qa', fQA, ...
    'ungradable', ung, 'refInRoutine', (tpRoutine + g * P.ai.uncertainShare * pi_ * (1 - se)) / ...
    max(fRoutine, eps), 'gradable', g);
X.se = se;
X.sp = sp;
X.tier = tier;
X.active = active;
X.isVan = isVan;
end
