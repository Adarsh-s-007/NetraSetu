# Validation protocol

This is the analysis plan the experiments implement. It was fixed before any
test image is screened: thresholds, splits and statistics come from the code,
not from looking at the test results.

## Target condition and reference standard

* **Referable diabetic retinopathy**: ICDR grade ≥ 2 (moderate NPDR or worse)
  **or referable diabetic macular oedema**, as graded by each dataset's own
  reference standard:
  * APTOS 2019 — Aravind Eye Hospital graders, ICDR 0–4, no DME label.
  * IDRiD — expert grades, ICDR 0–4 and DME 0–2 (2 = exudates within 1 DD of
    the fovea = referable).
  * Messidor-2 — adjudicated grades of Krause et al. (2018): DR 0–4, referable
    DME yes/no, gradability.
* **Programme target**: sensitivity > 0.90 and specificity > 0.85. A target is
  *met* only when the whole 95 % confidence interval clears it; a point
  estimate above the target with an interval that crosses it is reported as
  "not yet shown".

## Data partitions (no image is used twice)

| Partition | Source | Used for |
|---|---|---|
| train | APTOS 70 % + IDRiD grading train | lesion ensemble, CNN weights, 4-2-1 re-fit, NV normative model |
| val | APTOS 10 % | CNN early stopping, softmax temperature |
| fusion | APTOS 8 % | ordinal fusion of the branches (and of every ablation variant) |
| calib | APTOS 7 % | conformal quantile, referral operating point |
| internal test | APTOS 5 % | internal validation (optimistic: duplicates, same source) |
| external test 1 | IDRiD grading test (103) | India, different camera and graders |
| external test 2 | Messidor-2 (1,748 images / 874 patients) | France, different population, camera and graders |
| lesions / landmarks | IDRiD segmentation test (27) and localisation test (103) | detector accuracy, explanation quality |
| vessels | DRIVE (20 train / 20 test) | vessel detectors and their fusion |

APTOS is split grade-stratified with a fixed seed (2026); patient grouping is
applied wherever patient identifiers exist (Messidor-2 examinations).

## Index test

The deployed pipeline as it runs in the field: quality gate → enhancement →
anatomy → lesions → three graders → fusion → conformal set → triage, with the
operating point loaded from `models/calibration.mat`. Two binary readings are
reported:

* **model alone**: P(referable) ≥ threshold;
* **triage**: the eye is *not auto-cleared* (REFER, URGENT or HUMAN_REVIEW) —
  what the programme acts on; the human-review share is its workload price.

Images the pipeline cannot grade are counted two ways: excluded (per-protocol)
and as referrals (**intention to screen**), which is how a programme handles
them.

## Primary analysis

Sensitivity and specificity of the triage decision for referable DR on
Messidor-2, with 95 % Wilson intervals; per image and per patient (a patient
is positive if either eye is).

## Secondary analyses

* ROC AUC with DeLong 95 % CI; five-level quadratic weighted kappa with a
  bootstrap CI (1,000 resamples); confusion matrix.
* Calibration of P(referable): expected calibration error (10 bins), Brier score.
* Conformal sets: empirical coverage against the nominal 90 %, mean set size.
* **Integration vs single techniques, on the same eyes**: every branch
  combination (CNN, lesion ensemble, rule engine, pairs, all three), each at
  its own operating point chosen on the calibration split with the same
  guarantee; paired DeLong test of AUC against the deployed model, exact
  McNemar tests of the referral decision separately on referable eyes
  (sensitivity) and non-referable eyes (specificity).
* Lesion detection (IDRiD): pixel-level AUPR per lesion type over all pixels at
  native resolution (the challenge metric), microaneurysm FROC, optic-disc
  Jaccard; disc and fovea localisation error in pixels and disc diameters.
* Vessels (DRIVE): pixel AUC, Se/Sp/Acc/F1 at the threshold that maximises
  accuracy on the *training* images; the learned fusion against each
  detector, paired over images (bootstrap CI of the AUC difference, sign test).
* Explanations: pointing game and energy share of the evidence map, Grad-CAM
  and Grad-CAM++ on IDRiD lesion masks, their lift over a uniform map, and
  McNemar on pointing hits.
* Reader study: median review time, share of cases under 30 s and agreement
  with the AI, from the Reader Console logs.

## Reporting

`exp04` prints a STARD-style flow for each test set (images → without
reference grade → sent for recapture → failed → analysed, referable / not)
and writes `results/exp04/stard.txt`, `validation.csv` and the ROC figures;
`netra.eval.dossier` assembles every experiment into
`results/validation_dossier.html`, including the published context
(`netra.eval.benchmarks`) and the limitations.

## Statistical software checks

The statistics are implemented without toolboxes so they run anywhere, and
`tests/test_eval.m` checks them against independent implementations on fixed
data: ROC AUC, average precision, Brier score and quadratic weighted kappa
against scikit-learn; Wilson intervals, the exact McNemar test and the
proportional-odds model against statsmodels; DeLong's variance and paired test
against a midrank implementation (Sun & Xu, 2014).

## What would change the conclusions

* A **different population or camera** (e.g. a smartphone-based camera in a
  new district): re-run `exp03` steps 6–7 (fusion and calibration) on a few
  hundred locally graded eyes; the operating point is only guaranteed for the
  population it was calibrated on.
* **Lower prevalence** than in the test sets changes predictive values and the
  human-review share, not sensitivity and specificity.
* A prospective evaluation against local graders, with the Reader Console
  logging real review times, is the step between these results and clinical use.
