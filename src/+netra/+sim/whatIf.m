function W = whatIf(P, D, S)
%WHATIF Re-run a plan with one design choice flipped, on the same patients.
%   W = netra.sim.whatIf(P, D, S) returns runs for
%     base    the plan D as given
%     plain   the same plan with review WITHOUT the explainable console
%             (P.review.secondsPerCase.plain per case instead of .xai)
%     cloud   the same plan with every image uploaded and graded centrally
%     edge    the same plan with on-device grading
%   All share the scenario S (common random numbers), so differences are
%   caused by the design choice alone.
if nargin < 3 || isempty(S)
    S = netra.sim.scenario(P);
end
W = struct();
W.base = netra.sim.runReference(P, D, S);
d = D; d.reviewMode = 'plain';
W.plain = netra.sim.runReference(P, d, S);
d = D; d.aiMode = 'cloud';
W.cloud = netra.sim.runReference(P, d, S);
d = D; d.aiMode = 'edge';
W.edge = netra.sim.runReference(P, d, S);
end
