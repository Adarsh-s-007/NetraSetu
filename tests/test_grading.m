% Grading engine: ICDR rules, fusion, calibration, conformal sets,
% operating point and triage precedence.
cfg = netra.config();
s0 = struct('maCount', 0, 'maHighCount', 0, 'heCounts', struct('dot', 0, 'blot', 0, ...
    'flame', 0, 'preretinal', 0), 'heTotal', 0, 'hePerQuadrant', zeros(1, 4), ...
    'preretinalCount', 0, 'exCount', 0, 'exAreaDD2', 0, 'exMinDistFoveaDD', Inf, 'dme', 0, ...
    'centreInvolved', false, 'cwsCount', 0, 'vbQuadrants', [], 'vbMaxIndex', 0, ...
    'irmaQuadrants', [], 'nvdProb', 0, 'nveProb', 0, 'nvdScore', 0, 'nveScore', 0);

%% ICDR levels follow the clinical definitions
R = netra.grading.icdrRules(s0, cfg);
assert(R.grade == 0 && ~R.referable);
s = s0; s.maHighCount = 1; s.maCount = 1;
R = netra.grading.icdrRules(s, cfg);
assert(R.grade == 1);
s.heTotal = 2; s.heCounts.blot = 2; s.hePerQuadrant = [1 1 0 0];
R = netra.grading.icdrRules(s, cfg);
assert(R.grade == 2 && R.referableDR);
s.hePerQuadrant = [12 11 10 10];                    % 4-2-1: every quadrant above threshold
R = netra.grading.icdrRules(s, cfg);
assert(R.grade == 3);
s.hePerQuadrant = [12 11 10 3];
R = netra.grading.icdrRules(s, cfg);
assert(R.grade == 2, 'three quadrants are not enough');
s.vbQuadrants = [1 3];                              % beading in two quadrants
R = netra.grading.icdrRules(s, cfg);
assert(R.grade == 3);
s.nveProb = 0.8;
R = netra.grading.icdrRules(s, cfg);
assert(R.grade == 4 && strcmp(R.criteria([R.criteria.met] & [R.criteria.level] == 4).id, 'nv'));

%% DME grade 2 alone makes an eye referable, and every met criterion is explained
s = s0; s.exCount = 3; s.dme = 2; s.exMinDistFoveaDD = 0.6;
R = netra.grading.icdrRules(s, cfg);
assert(R.grade == 2 && R.referable);
assert(any(~cellfun(@isempty, strfind(R.evidence, 'Macular oedema risk 2'))));

%% Log-opinion pool: identical branches give back the same distribution
p = [0.5 0.2 0.15 0.1 0.05];
Fz = netra.grading.fuse(struct('cnn', p, 'lesion', p, 'rules', p), []);
assert(max(abs(Fz.P - p)) < 1e-12);
assert(abs(Fz.pReferable - 0.3) < 1e-12 && Fz.grade == 0 && Fz.disagreement == 0);
Fz = netra.grading.fuse(struct('rules', p), []);   % one branch: weights renormalise
assert(max(abs(Fz.P - p)) < 1e-12);

%% Batch fusion equals the per-eye fusion
rng(5);
B = struct('cnn', netra.util.softmax(randn(20, 5), 2), 'rules', netra.util.softmax(randn(20, 5), 2));
P = netra.eval.fusedP(B, []);
for i = [1 7 20]
    Fz = netra.grading.fuse(struct('cnn', B.cnn(i, :), 'rules', B.rules(i, :)), []);
    assert(max(abs(P(i, :) - Fz.P)) < 1e-12);
end

%% Temperature scaling recovers the temperature that generated the labels
rng(4);
z = 2 * randn(3000, 5);
Pt = netra.util.softmax(z / 2.5, 2);
u = rand(3000, 1);
y = sum(repmat(u, 1, 5) > cumsum(Pt, 2), 2);
T = netra.grading.temperatureScale(z, y);
assert(abs(T - 2.5) < 0.2, 'T = %.3f', T);

%% Split-conformal sets reach their coverage on exchangeable data
rng(4);
z = 2 * randn(3000, 5);
Pt = netra.util.softmax(z / 2.5, 2);
y = sum(repmat(rand(3000, 1), 1, 5) > cumsum(Pt, 2), 2);
C = netra.grading.conformal('calibrate', Pt(1:1500, :), y(1:1500), 0.1);
sets = netra.grading.conformal('predict', Pt(1501:end, :), C);
cover = mean(sets(sub2ind(size(sets), (1:1500)', y(1501:end) + 1)));
assert(cover >= 0.88, 'coverage %.3f', cover);
for i = 1:size(sets, 1)
    k = find(sets(i, :));
    assert(~isempty(k) && k(end) - k(1) + 1 == numel(k), 'set %d is not a contiguous range', i);
end

%% Operating point: the Wilson lower bound of sensitivity meets the target
rng(9);
lab = rand(400, 1) < 0.3;
score = lab + 0.9 * randn(400, 1);
op = netra.grading.operatingPoint(score, lab, 'Target', 0.9);
assert(op.seCI(1) >= 0.9 - 1e-12, 'lower bound %.3f', op.seCI(1));
assert(abs(op.se - mean(score(lab) >= op.threshold)) < 1e-12);

%% Trained ordinal fusion predicts proper distributions
rng(2);
n = 300;
g = randi([0 4], n, 1);
mk = @(shift) netra.util.softmax(-((repmat(0:4, n, 1) - repmat(g + shift * randn(n, 1), 1, 5)) .^ 2), 2);
Bt = struct('cnn', mk(0.6), 'rules', mk(1.2));
F = netra.grading.trainFusion(Bt, g, 'Branches', {'cnn', 'rules'});
Pf = netra.eval.fusedP(Bt, F);
assert(max(abs(sum(Pf, 2) - 1)) < 1e-10 && all(Pf(:) >= 0));
gf = sum(cumsum(Pf, 2) < 0.5, 2);
assert(netra.eval.qwk(g, gf, 5) > 0.8);

%% Triage precedence: recapture, urgent, refer, review, routine
Q = struct('decision', 'GRADABLE', 'score', 0.9, 'feedback', struct('en', {}, 'hi', {}));
Rr = netra.grading.icdrRules(s0, cfg);
Fz = struct('P', [0.9 0.05 0.03 0.01 0.01], 'pReferable', 0.05, 'pUrgent', 0.01, 'grade', 0, ...
    'disagreement', 0, 'branchNames', {{'rules'}}, 'branchGrades', 0);
T = netra.grading.decide(Q, Rr, Fz, [], [], [], cfg);
assert(strcmp(T.triage, 'ROUTINE'));
T = netra.grading.decide(Q, Rr, Fz, logical([1 1 1 0 0]), [], [], cfg);
assert(strcmp(T.triage, 'HUMAN_REVIEW'), 'a set spanning the referral boundary needs a human');
Fz2 = Fz; Fz2.pReferable = 0.95;
T = netra.grading.decide(Q, Rr, Fz2, [], [], [], cfg);
assert(strcmp(T.triage, 'REFER'));
Fz2.pUrgent = 0.6;
T = netra.grading.decide(Q, Rr, Fz2, [], [], [], cfg);
assert(strcmp(T.triage, 'URGENT'));
Rd = Rr; Rd.dme = 2;                               % exudates within 1 DD of the fovea
T = netra.grading.decide(Q, Rd, Fz, [], [], [], cfg);
assert(strcmp(T.triage, 'REFER') && ~isempty(strfind(T.followUp, '2 weeks')));
assert(isempty(strfind(T.message.en, '4 weeks')), 'one timeframe per message');
Q.decision = 'RECAPTURE';
T = netra.grading.decide(Q, Rr, Fz2, [], [], [], cfg);
assert(strcmp(T.triage, 'RECAPTURE'));
assert(~isempty(T.message.hi) && ~isempty(T.message.en));

%% Lesion feature names are stable and complete
[x, names] = netra.grading.lesionFeatures();
assert(numel(names) == 32 && numel(x) == 32 && numel(unique(names)) == 32);
