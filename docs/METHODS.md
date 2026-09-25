# Methods

This document describes what each stage of NetraSetu computes and why it was
designed that way. Parameter values are the defaults in
[`src/+netra/config.m`](../src/+netra/config.m); every one of them can be
overridden (`netra.config('grading.referralThreshold', 0.3)` or a JSON file).

Distances on the retina are expressed in **disc diameters (DD)**, measured on
each image (1 DD = 1500 µm by the ETDRS convention), so thresholds mean the
same thing on a 565-pixel DRIVE image and a 4288-pixel IDRiD photograph.

---

## 1. Quality gate — `netra.quality.assess`

A grader rejects a photograph for a handful of reasons; the gate measures each
of them separately so the technician can be told *which* one to fix.

| Sub-score | Measurement | Why this one |
|---|---|---|
| field | visible fraction of the fitted aperture disc; lid/lash shadow inside the frame | clipped captures are normal (IDRiD, APTOS); lost retina is not |
| focus | energy ratio of Laplacian-of-Gaussian responses at σ = 1 and 2 px on the vessel-rich green channel, penalised by noise | a blurred edge loses fine-scale energy faster than coarse-scale energy; the *ratio* does not depend on how many vessels the eye has |
| illumination | mean luminance, dark and saturated fractions, background uniformity | under-exposure through small pupils is the commonest failure of non-mydriatic cameras |
| contrast | P97 − P50 darkening of the illumination-normalised green channel | vessels must stand out from the background to be graded |
| artefact | lash shadow, corneal flare, haze | local, fixable at capture |

Each measurement is mapped to [0, 1] by a logistic curve (centre, width in the
config); the overall score is a weighted geometric mean, and the decision uses
both the score and a **minimum-sub-score rule**: an image is `GRADABLE` only if
every criterion passes (≥ 0.5), `RECAPTURE` if any criterion fails badly
(< 0.15) or the score is < 0.35, and `ENHANCE` in between — borderline images
are enhanced and re-assessed, and if they still are not clean they reach a
human instead of the automatic "normal". Feedback strings are bilingual
([`tools/i18n/strings.tsv`](../tools/i18n/strings.tsv)).

## 2. Standardisation and enhancement — `netra.quality.fovMask / standardize / enhance`

* **Aperture.** Thresholding the brightest channel at 35 % of Otsu's level and
  fitting a circle (robust Kåsa fit) to boundary points *not* on the image
  frame recovers the true radius even when the top and bottom of the circle
  are cut off.
* **Canvas.** The photograph is resampled so that the aperture diameter is
  1024 px with a 2 % margin (anti-aliased resize, identical in MATLAB and
  Octave). All coordinates can be mapped back (`toOriginal`, `warpToOriginal`)
  to score results at a benchmark's native resolution.
* **Illumination.** A two-pass background estimate (median filter at quarter
  resolution, then normalised convolution that ignores vessels and lesions —
  the approach of Foracchia et al., 2005) divides out vignetting and flash
  tilt: in `gN`, 0.8 means "20 % darker than the local retina". Every lesion
  threshold is written in these contrast units.
* **Colour and contrast.** Each channel is divided by its own background and
  re-coloured to a reference fundus colour; the display image gets CLAHE on
  Lab lightness with a clip limit adapted to the measured contrast; noise is
  measured (Immerkær) and removed by non-local means only when it is high.

## 3. Anatomy — `netra.anatomy.*`

**Vessels** are segmented at DRIVE-like resolution (560 px FOV) by three
complementary detectors on the inverted green contrast:

1. multiscale **Frangi** vesselness (Hessian eigenvalues; also gives the vessel direction),
2. the multiscale **line detector** of Nguyen et al. (2013),
3. the supremum of **linear openings** (Zana & Klein, 2001), which keeps only
   elongated structures and therefore ignores microaneurysms and haemorrhages.

Responses are robustly normalised (FOV median → 0, 99th percentile → 1) and
fused — by default a weighted average, or a **logistic model learned on the
DRIVE training images** (`exp01` writes `models/vessel_fusion.mat`). The mask
is obtained by hysteresis (seeds: top 7.5 % of FOV pixels, growth into the top
12.5 %); compact wide components (fovea, blot haemorrhages) are removed and
handed to the lesion stage. `exp01` measures what the fusion adds over each
detector on the same test images.

**Optic disc.** Four independent cues on a 512-px FOV — brightness
(difference of Gaussians), density of thick vessels, density of *vertical*
vessels and vessel **convergence** (a Hough-like vote along vessel
directions) — are converted to capped z-scores and combined; the vessel cues
are gated by brightness so a haemorrhage cluster cannot win. The candidate is
refined by closing (to remove vessels), Otsu and a circle fit; the measured
diameter sets the image's DD when plausible (otherwise the 0.14 × FOV prior).
**Fovea**: the darkest avascular region 2.5 DD temporal to and 0.3 DD below
the disc, found on a closing-filtered image with a vessel-density penalty and a
Gaussian position prior. The **ETDRS frame** (quadrants ST/SN/IN/IT, rings at
1/3, 1 and 2 DD) anchors the 4-2-1 rule and the macular-oedema zones.

## 4. Lesions — `netra.lesions.*`

**Microaneurysms, measured to a fraction of a pixel.**
Vessels are suppressed by subtracting the supremum of 12 linear openings of
length 0.2 DD from the darkening image; candidates are scale-normalised
Laplacian-of-Gaussian maxima (σ = 9–63 µm) ranked by response. Each candidate
is fitted by **Levenberg–Marquardt** with an isotropic Gaussian on a tilted
plane:

  f(x, y) = b₀ + bₓ(x − x_c) + b_y(y − y_c) + a·exp(−((x − x₀)² + (y − y₀)²) / 2s²)

giving a sub-pixel centre, width, amplitude, goodness of fit, the standard
error of the centre and the Cramér–Rao bound σ ≥ √(2/π)·σ_n/a. The
probability of being a microaneurysm is a transparent product of soft
criteria — SNR against the *local* background texture, R², size (15–125 µm),
roundness (Hessian eigenvalue ratio), redness, a minimum visible amplitude,
and an **isolation test** (no vessel leaving the dot, from the ring profile
around it). Red dots of 125–250 µm become dot haemorrhages. On simulated spots
the fit's error sits on the Cramér–Rao bound from an SNR of about 8 upwards
(0.15 px at SNR 8, 0.04 px at SNR 30), where the brightest pixel stays
0.4–0.7 px off ([`docs/img/subpixel.png`](img/subpixel.png)); below SNR ≈ 6 a
fit can lock onto noise, which the SNR and fit-quality criteria guard against.

**Haemorrhages.** After removing the smooth foveal depression, dark regions
above an adaptive level are opened with a ~60 µm disc (which removes vessels
narrower than ~120 µm) and major vessel trunks are subtracted. Morphology
follows where the blood lies: dot (≤ 250 µm, round), blot, flame (elongated
along the nerve-fibre direction, approximated by the disc-radial direction),
pre-retinal (≥ 1 disc area and very dark — a PDR sign). Counts per quadrant
feed the 4-2-1 rule.

**Exudates and cotton-wool spots.** Bright candidates (hysteresis) outside the
disc region are described by boundary **sharpness** (gradient / contrast),
Lab **b\*** yellowness excess, size, elongation and whether they hug a major
vessel (the nerve-fibre-layer sheen of young eyes). Exudates are sharp or
yellow; cotton-wool spots are fluffy, white, round and compact. Distance of
the nearest exudate to the fovea gives the macular-oedema risk (IDRiD
protocol: grade 2 within 1 DD) and a centre-involving flag (within ~500 µm).

**Neovascularisation.** On a fine-vessel map at canvas resolution, windows of
0.5 DD are described by branch density, orientation entropy, tortuosity, loops
and vessel length; one-sided robust z-scores (capped at 3 per feature, so no
single feature decides) are summed and compared zone by zone (disc zone vs
the rest), against population statistics from grade-0 eyes when
`models/nv_normative.mat` exists. **Venous beading**: calibre along each major
vein measured by sub-pixel FWHM cross-sections; beading index = s.d. of the
detrended calibre / mean calibre, confirmed by the periodicity of its
autocorrelation. **IRMA-like** anomalies: moderately abnormal texture near
clusters of haemorrhages, not reaching the NV threshold.

These three detectors are the least mature parts of the system (see
[Limitations](#9-limitations)); PDR is also caught by the CNN branch and by
the human-review rules.

## 5. Grading — `netra.grading.*`

Three branches produce a distribution over the ICDR grades 0–4:

**Rule engine** (`icdrRules`, `probabilisticRules`). The International
Clinical DR scale written as explicit criteria, each with its measured value,
threshold and a sentence a grader can verify on the annotated image: MA only
→ 1; any haemorrhage, exudate or cotton-wool spot → 2; the **4-2-1 rule**
(haemorrhages in 4 quadrants, venous beading in 2, IRMA in 1) → 3; NV or
pre-retinal haemorrhage → 4. The 4-2-1 rule was defined on seven-field
photography; one 45° field shows about half of each mid-peripheral quadrant,
so the haemorrhage count per quadrant (default 10, not 20) and the number of
quadrants are **re-fitted on training data** (`exp03`, maximum quadratic
weighted kappa). Because detections are uncertain, a Monte-Carlo version
samples each lesion as present with its own probability (256 draws), applies
the rules to every sampled "world" and returns the grade frequencies —
with an evidence floor (scores below 0.3 count as absent) and 10 % shrinkage to
a typical screening case-mix, so that no grade has probability zero.

**Lesion ensemble** (`lesionFeatures`, `lesionModel`). 32 features with
clinical names (MA count and soft count, haemorrhages by type and quadrant,
exudate area and distance to the fovea, NV scores, image quality, disc and
fovea confidence …) feed bagged decision trees with class-balanced weights;
training returns out-of-fold posteriors, and `explain` returns Shapley values
of P(referable) for one eye — the report lists the findings that pushed it.

**CNN** (`+cnn`). An ImageNet backbone (ResNet-50 by default; ResNet-18 or
EfficientNet-B0 for CPUs) re-headed for five grades, input 448 px after
Graham's local-colour subtraction, trained with class-weighted cross-entropy
**plus an expected ordinal cost** (λ·Σ_k P_k·((k − y)/4)²), so "moderate
predicted as proliferative" costs more than "moderate predicted as severe".
Augmentation: rotation (0–360°), flips, ±10 % brightness/contrast. Early
stopping on the validation split; **temperature scaling** (Guo et al., 2017)
on the same split; four-view test-time augmentation at inference.

**Fusion** (`trainFusion`, `fuse`). The branches enter a
**proportional-odds (cumulative-logit) model** as their cumulative logits
logit P_b(grade ≥ k): one interpretable slope per branch and boundary, fitted
on eyes no branch has seen (the *fusion* split). Without a trained model, a
logarithmic opinion pool (CNN 0.5, lesions 0.3, rules 0.2, renormalised over
the available branches) is used. The fused grade is the ordinal median.

**Uncertainty.**
* **Split-conformal grade sets** (`conformal`): score s = 1 − P(true grade) on
  the calibration split, quantile at ⌈(n + 1)(1 − α)⌉/n (α = 0.1); sets are
  closed into contiguous grade ranges (a superset, so coverage is kept).
  Under exchangeability the true grade lies in the set for ≥ 90 % of eyes.
* **Operating point** (`operatingPoint`): the highest threshold on
  P(referable) whose sensitivity on the calibration split is at least 0.90
  **as the lower bound of its 95 % Wilson interval**, not as a point
  estimate. A small calibration set pays for the guarantee with a lower
  threshold — the right trade-off for screening.

## 6. Triage — `netra.grading.decide`

First match wins:

1. **RECAPTURE** — the photograph cannot be graded (reasons from the quality gate).
2. **URGENT** — P(PDR) ≥ 0.35, NV or pre-retinal haemorrhage in the evidence,
   or exudates within ~500 µm of the fovea.
3. **REFER** — P(referable) ≥ the calibrated threshold, or DME grade 2.
4. **HUMAN_REVIEW** — anything that makes an automatic "normal" unsafe: a
   conformal set spanning the referral boundary, branches disagreeing by ≥ 2
   grades, borderline quality, anatomy not found, or a CNN whose attention
   does not coincide with the detected lesions.
5. **ROUTINE** — re-screen in 12 months; 5 % of these are sampled for audit.

Every referral is confirmed by a person in the programme workflow; the
explanation exists so that the confirmation takes seconds, not minutes.

## 7. Explanation — `netra.xai.*`

* **Grad-CAM / Grad-CAM++** (Selvaraju et al., 2017; Chattopadhay et al.,
  2018) computed with `dlfeval`/`dlgradient` at the layer feeding global
  pooling, for the **log-odds of referable DR**
  (logsumexp(z₂, z₃, z₄) − logsumexp(z₀, z₁)) rather than for one grade —
  it answers "what made this eye referable?". Grad-CAM++ spreads credit over
  the many small lesions typical of DR.
* **Evidence map**: the classical detections, weighted by clinical severity
  and smoothed — shown instead of Grad-CAM when no CNN is loaded.
* **Attention–evidence concordance**: share of CAM energy on the (dilated)
  lesions, recall of lesion components under the top 20 % of attention, and
  the pointing game; low concordance sends the eye to a human. Two
  independent techniques agreeing is the explanation; either alone is only a
  picture. `exp05` scores both against IDRiD's pixel-level lesion masks.
* **Report** (`reportFigure`, `reportHTML`): annotated fundus with ETDRS grid
  and every lesion (rings for MAs so the lesion stays visible, outlines
  coloured by type, distinguishable for colour-vision deficiency), the
  attention map, grade probabilities with the conformal bracket, the ICDR
  criteria with measured values and thresholds, quality sub-scores and
  provenance. The HTML version is self-contained (~0.3 MB), bilingual
  (Devanagari shaped by the browser) and works on a phone.
* **Reader console** (`netra.ui.ReaderConsole`): a keyboard-first review app —
  Enter agrees, 0–4 overrides the grade, R/E/L/A switch between raw,
  enhanced, lesion and attention views — with a stopwatch, an audit log (CSV)
  and session statistics (median time, share under 30 s, agreement, QWK).

## 8. District simulation — `netra.sim.*`

The programme is modelled hour by hour for a year:

* **Demand**: Poisson arrivals at each PHC's NCD clinic and at mobile camps,
  with weekday, seasonal (monsoon) and holiday effects.
* **Capture**: cameras per site, minutes per patient including recapture;
  patients still waiting at closing time go home unscreened.
* **Uplink**: each site's link (2G / 3G / 4G / fibre) is a two-state Markov
  chain with the tier's availability and mean outage duration; uploads run in
  clinic hours (vans upload in the evening); throughput = link rate ×
  efficiency / image size.
* **AI**: *edge* (graded on the PHC laptop in seconds; only flagged and audit
  eyes are uploaded; the patient is counselled on the spot) or *cloud*
  (every image uploaded and graded centrally). Triage fractions follow from
  the operating point on the ROC curve — binormal with AUC 0.95 by default,
  or **the measured ROC from `exp04`** once it exists.
* **Review**: graders (urgent > routine > audit priority) and an
  ophthalmologist block for adjudication, with seconds per case for the
  explainable console (30 s) vs plain image review (150 s).

Patients are tracked as **age-structured cohorts** (hours since capture), and
every queue serves the oldest first, so the age at which a cohort leaves the
last queue *is* its turnaround — exact percentiles without simulating
individuals. KPIs: screens, turnaround P50/P95 by path, utilisation, programme
sensitivity (AI sensitivity plus the audit's catch), patients reaching
treatment (uptake decays after the patient leaves the PHC), annual cost in
rupees. **Scenarios use common random numbers**, so two plans face the same
patients and the same outages and their difference is caused by the plan.
The optimiser minimises cost subject to the targets (100,000 screens/year,
routine result ≤ 72 h and urgent notice ≤ 24 h at P95, utilisation ≤ 85 %,
programme sensitivity ≥ 0.90) with `bayesopt` or, anywhere, a two-stage
search (coverage ranked analytically, operations tuned by simulation).

**Simulink.** `netra.sim.simulinkBlocks` describes the model once: seven
MATLAB Function stages (capture, route, uplink, grade, review,
ophthalmologist, results) whose queues are persistent state, From Workspace
inputs and To Workspace logs. `buildSimulink` draws the `.slx` from it;
`emulateBlocks` executes the very same block code without Simulink, and the
tests require it to match the MATLAB reference exactly (every logged signal
at every hour and every KPI) — so the model's logic is verified continuously
even where Simulink is not installed.

## 9. Limitations

* Single-field adaptation of the 4-2-1 rule; severe NPDR from one 45° field
  is an approximation of seven-field grading.
* NV, venous beading and IRMA detectors are heuristic and the least mature
  components.
* Public datasets carry their own reference standards and case-mix; APTOS has
  duplicates and no patient identifiers.
* Prevalence in a district programme is lower than in these datasets; the
  calibration (and the human-review share) must be refreshed on local data.
* The simulation's parameters are illustrative assumptions to be replaced by
  local data; its outputs are planning estimates.
* Research software, not a medical device; prospective validation with local
  graders is required before clinical use.

## References

Abràmoff MD et al. Improved automated detection of diabetic retinopathy on a publicly available dataset through integration of deep learning. *IOVS* 2016;57:5200–6. ·
Angelopoulos AN, Bates S. A gentle introduction to conformal prediction. arXiv:2107.07511, 2021. ·
Chattopadhay A et al. Grad-CAM++. *WACV* 2018. ·
DeLong ER, DeLong DM, Clarke-Pearson DL. Comparing the areas under correlated ROC curves. *Biometrics* 1988;44:837–45. ·
Foracchia M, Grisan E, Ruggeri A. Luminosity and contrast normalization in retinal images. *Med Image Anal* 2005;9:179–90. ·
Frangi AF et al. Multiscale vessel enhancement filtering. *MICCAI* 1998. ·
Gulshan V et al. Development and validation of a deep learning algorithm for detection of diabetic retinopathy. *JAMA* 2016;316:2402–10. ·
Guo C et al. On calibration of modern neural networks. *ICML* 2017. ·
Nguyen UTV et al. An effective retinal blood vessel segmentation method using multi-scale line detection. *Pattern Recognit* 2013;46:703–15. ·
Niemeijer M et al. Retinopathy Online Challenge. *IEEE TMI* 2010;29:185–95. ·
Porwal P et al. IDRiD: Diabetic Retinopathy – Segmentation and Grading Challenge. *Med Image Anal* 2020;59:101561. ·
Selvaraju RR et al. Grad-CAM. *ICCV* 2017. ·
Staal J et al. Ridge-based vessel segmentation in color images of the retina. *IEEE TMI* 2004;23:501–9. ·
Wilkinson CP et al. Proposed international clinical diabetic retinopathy and diabetic macular edema disease severity scales. *Ophthalmology* 2003;110:1677–82. ·
Zana F, Klein JC. Segmentation of vessel-like patterns using mathematical morphology and curvature evaluation. *IEEE TIP* 2001;10:1010–9.
