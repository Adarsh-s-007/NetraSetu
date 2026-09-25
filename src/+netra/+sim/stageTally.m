function H = stageTally(H, autoNow, autoByAge, doneU, doneR, doneOU, doneOR, p)
%STAGETALLY Accumulate completed results by turnaround (age) and path.
%   H rows: 1 AI-cleared, 2 routine referral confirmed, 3 urgent referral
%   sent (after grader confirmation), 4 urgent confirmed by ophthalmologist.
H(1, 1) = H(1, 1) + autoNow;
H(1, :) = H(1, :) + autoByAge;
H(2, :) = H(2, :) + doneR * (1 - p(7)) + doneOR;
H(3, :) = H(3, :) + doneU;
H(4, :) = H(4, :) + doneOU;
end
