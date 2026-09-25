# Clinical safety case

NetraSetu is research software. This document records how it is meant to be
used, how it can fail, and what in the design contains each failure — the
starting point of a hazard log, not a certificate.

## Intended use

Triage of colour fundus photographs of adults with diabetes, taken at primary
health centres or screening camps, into *retake now*, *urgent referral*,
*referral*, *specialist review of the images* or *re-screen in 12 months*.
Every referral and every uncertain case is confirmed by a trained grader or
an ophthalmologist; the software shortens that confirmation, it does not
replace it. Not intended for: diagnosis, other retinal diseases (glaucoma,
AMD, retinal vein occlusion are not detected and are not excluded), children,
or images from cameras it has not been calibrated on.

## Human in the loop

| Decision | Who acts | What the software provides |
|---|---|---|
| RECAPTURE | technician, immediately | which quality criterion failed, in Hindi and English |
| URGENT / REFER | grader confirms, patient counselled | annotated image, criteria with values, attention map, probabilities |
| HUMAN_REVIEW | grader or ophthalmologist | *why* the eye was not cleared (uncertain set, disagreement, quality, anatomy, attention) |
| ROUTINE | nobody, except the 5 % audit sample | the full report is kept; audit catches systematic misses |

## Hazards and controls

| Hazard | Cause | Controls in the design | Residual risk / monitoring |
|---|---|---|---|
| Referable eye auto-cleared | detector or CNN miss | sensitivity-guaranteed threshold (Wilson lower bound ≥ 0.90 on calibration data); conformal set spanning the referral boundary → human; branch disagreement ≥ 2 grades → human; 5 % audit of ROUTINE | measured in `exp04` (triage sensitivity with CI); audit misses should trigger recalibration |
| Proliferative DR not recognised as urgent | NV detectors are weak | URGENT on P(PDR) ≥ 0.35 (CNN-driven), on NV or pre-retinal haemorrhage evidence; PDR is referable anyway, so it is at least referred | NV detection is the least mature component; track PDR sensitivity separately |
| Ungradable image graded | blur, small pupil, lashes, flare | five-criterion quality gate with a minimum-sub-score rule; borderline images re-assessed after enhancement and sent to a human if not clean | intention-to-screen analysis counts recaptures as referrals |
| Explanation misleads the reader | CNN attends to artefacts or the disc | attention-evidence concordance; low concordance → HUMAN_REVIEW; the lesion evidence (independent method) is always shown | `exp05` measures pointing accuracy on IDRiD masks |
| Anatomy wrong (quadrants, macula) | disc or fovea not found | four-cue disc detector with confidence; geometry consistency check; flags → HUMAN_REVIEW | `exp02` localisation error; flags visible on the report |
| Model drifts in a new district | different camera, population, prevalence | calibration artefacts record their data; reports state which components produced the grade; recalibration procedure in `docs/VALIDATION.md` | periodic comparison of audit results with the calibration figures |
| Result lost or delayed | link outages, reviewer backlog | edge grading gives the patient a provisional answer on site; store-and-forward queues; the district model sizes reviewers and links to the turnaround targets | simulated, not observed: validate turnaround in the pilot |
| Wrong patient / wrong eye | data entry | report carries ID, eye, site and time; HTML report travels with the case | operational controls outside the software |

## What the report always shows

The triage decision in its colour, the follow-up interval, the patient
message in English and Hindi, the annotated photograph, the attention or
evidence map, the grade probabilities with the conformal set, the ICDR
criteria with measured values and thresholds, the quality sub-scores, which
trained components produced the result, and the disclaimer that a qualified
grader or ophthalmologist confirms every referral.

## Before clinical use

1. Recalibrate on locally graded images from the cameras in use (`exp03` steps 6–7).
2. Prospective accuracy study against local graders, with intention-to-screen analysis.
3. Reader study with the Reader Console in the actual workflow (time, agreement, overrides).
4. Regulatory assessment under the applicable medical-device rules.
