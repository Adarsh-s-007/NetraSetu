function [qOU, qOR, doneOU, doneOR, cases] = stageOphth(qOU, qOR, doneU, doneR, capO, p)
%STAGEOPHTH Ophthalmologist adjudication: every urgent case, a share of routine.
%   p(7) = share of grader-confirmed routine referrals that are adjudicated.
[qOU, doneOU, nU] = netra.sim.ageQueue(qOU, doneU, capO);
[qOR, doneOR, nR] = netra.sim.ageQueue(qOR, doneR * p(7), capO - nU);
cases = nU + nR;
end
