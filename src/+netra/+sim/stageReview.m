function [qU, qR, qQ, doneU, doneR, doneQ, cases] = stageReview(qU, qR, qQ, inU, inR, inQ, capG)
%STAGEREVIEW Grader review with strict priority: urgent > routine > audit.
[qU, doneU, nU] = netra.sim.ageQueue(qU, inU, capG);
[qR, doneR, nR] = netra.sim.ageQueue(qR, inR, capG - nU);
[qQ, doneQ, nQ] = netra.sim.ageQueue(qQ, inQ, capG - nU - nR);
cases = nU + nR + nQ;
end
