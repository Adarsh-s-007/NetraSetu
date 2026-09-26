<div align="center">

# NetraSetu &nbsp;·&nbsp; नेत्रसेतु

**A bridge for the eyes: explainable diabetic-retinopathy screening for rural India, from one photograph to a whole district.**

MATLAB · Image Processing · Computer Vision · Deep Learning · Statistics & ML · Simulink &nbsp;|&nbsp; also runs in GNU Octave

**[Live demo](https://adarsh-s-007.github.io/NetraSetu/)** in English and हिंदी, laid out like a screening clinic's software. Record the patient, add a fundus photograph, and the pipeline runs on your own device: quality check, numbered lesion markers on a zoomable workstation (colour, red-free, enhanced, evidence map), ICDR grade probabilities, a follow-up date and a message for the patient. Each study then waits in a review queue with its one-page report and a timed 30-second review; the district planner and the published benchmarks have their own tabs ([`docs/index.html`](docs/index.html) and [`docs/app.js`](docs/app.js) with [`docs/engine.js`](docs/engine.js), served by GitHub Pages from `docs/`)

</div>

<p align="center"><img src="docs/img/pipeline.svg" alt="NetraSetu architecture: capture, quality gate, standardisation, anatomy, lesions, three graders, ordinal fusion, conformal calibration, triage, explained report, reader console, district simulation" width="100%"></p>

A technician at a primary health centre photographs both eyes of a person with
diabetes. In under a minute on a laptop CPU, NetraSetu says whether the photograph is good enough
(and, in Hindi or English, what to fix if it is not), finds the optic disc,
fovea and vessels, **measures** every lesion the international grading scale
is written in — microaneurysms to a fraction of a pixel, haemorrhages by type
and quadrant, exudates by distance from the fovea, new vessels — grades the
eye three independent ways, fuses the grades with calibrated uncertainty, and
produces a one-page report designed to be confirmed by a grader in under 30
seconds. A
Simulink model of the district programme then answers the question the
district health officer actually has: *how many cameras, links, graders and
ophthalmologist hours does it take to screen 100,000 people a year, and what
does it cost?*

> **Status, honestly.** Everything in the section *Measured here* was run in
> this repository. The clinical accuracy figures (sensitivity, specificity,
> AUC on APTOS 2019, IDRiD and Messidor-2) are produced when you run
> `experiments/run_all.m` with the datasets, which are licensed and cannot be
> redistributed; the analysis plan is fixed in
> [`docs/VALIDATION.md`](docs/VALIDATION.md) and the results are assembled into
> a self-contained validation dossier. No number in this README is a clinical
> accuracy claim. The MATLAB-only parts — CNN training and Grad-CAM, the lesion
> ensemble, the Reader Console and building the `.slx` — follow the documented
> MATLAB APIs but could not be executed here (no MATLAB in this environment);
> run `matlab_smoke` in MATLAB first. In about five minutes and without any
> dataset it trains a small CNN, runs Grad-CAM++, the lesion ensemble and the
> Reader Console, and builds the `.slx` and cross-checks it against the
> MATLAB reference.

---

## What it does

| | |
|---|---|
| **1 · Quality gate** | Five interpretable sub-scores — field, focus, illumination, contrast, artefacts — and a minimum-sub-score rule. *GRADABLE*, *ENHANCE* (enhanced, re-assessed, and sent to a person if still borderline) or *RECAPTURE* with the reason, in the technician's language. |
| **2 · Standardise** | Aperture circle recovered even when a camera clips it; 1024-px canvas where 1 disc diameter ≈ 1500 µm; illumination and colour normalised (every lesion threshold is a contrast in *% darker than the local retina*); adaptive CLAHE; denoising only when noise is measured to be high. |
| **3 · Anatomy** | Vessels by three complementary detectors (Frangi, multiscale line detector, linear top-hat) fused by a model learned on DRIVE; optic disc from four independent cues; fovea; ETDRS grid, quadrants and macular zones. |
| **4 · Lesions, measured** | Microaneurysms fitted with a sub-pixel Gaussian (on simulated spots the error sits on the Cramér–Rao bound); haemorrhages as dot / blot / flame / pre-retinal, counted per quadrant; hard exudates vs cotton-wool spots; macular-oedema zones; neovascularisation on and off the disc; venous beading; IRMA-like anomalies. |
| **5 · Three graders** | An ICDR **rule engine** (the 4-2-1 rule, re-fitted for one 45° field, run as a Monte-Carlo over uncertain lesions) · a **lesion ensemble** on 32 clinically named features with Shapley explanations · a **CNN** (ResNet-50, ordinal-cost loss, test-time augmentation, temperature-scaled). |
| **6 · Fusion & uncertainty** | Proportional-odds stacking of the branches; split-conformal grade sets with 90 % coverage; a referral threshold whose sensitivity is *guaranteed* by the lower bound of its Wilson interval, not just its point estimate. |
| **7 · Triage** | RECAPTURE › URGENT › REFER › HUMAN REVIEW › ROUTINE. An eye is auto-cleared only when nothing is uncertain: a grade set straddling the referral boundary, disagreeing branches, borderline quality, anatomy not found, or a CNN looking somewhere other than the lesions all go to a person. |
| **8 · Explanation** | Grad-CAM++ on the log-odds of *referable* DR, checked against the classical lesion evidence (attention–evidence concordance); every ICDR criterion with its measured value and threshold; A4 report and a 0.3 MB bilingual HTML report; a keyboard-first Reader Console with a 30-second stopwatch and an audit log. |
| **9 · District model** | Hour-by-hour simulation of a year — Poisson demand with seasons and holidays, cameras, Markov link outages, edge vs cloud AI, graders and ophthalmologist — as a Simulink model and a MATLAB reference that share every line of stage code; an optimiser finds the cheapest plan that meets every target. |

## See it

<table>
<tr><td width="50%"><img src="docs/img/report.jpg" alt="One-page screening report of a severe NPDR phantom"></td>
<td width="50%"><img src="docs/img/report_html.png" alt="Bilingual HTML report"></td></tr>
<tr><td><b>The report</b> a grader confirms: triage and follow-up, annotated fundus with ETDRS grid and every lesion, attention map, grade probabilities with the conformal set, the ICDR criteria that fired with their values, image quality, provenance.</td>
<td><b>The same result as a self-contained HTML page</b> (English and हिन्दी, images embedded, ~0.3 MB) that opens on an ASHA worker's phone over 2G.</td></tr>
</table>

<p align="center"><img src="docs/img/phantoms.jpg" alt="Synthetic eyes of ICDR grades 0 to 4 and NetraSetu's annotation of each" width="100%"></p>
<p align="center"><sub>Synthetic eyes, ICDR 0 → 4 (top), rendered with a physical model — pigmented background, Beer–Lambert blood, reflectance deposits, camera optics and noise — so every lesion is known exactly; NetraSetu's annotation of each (bottom). Rings: microaneurysms; violet outlines: haemorrhages; yellow: exudates; ice blue: cotton-wool spots; green box: new vessels; grid: ETDRS. Triage: 0 and 1 → ROUTINE, 2, 3 and 4 → REFER. The grade-4 eye is referred but not flagged URGENT: its new vessels were not detected — neovascularisation is the least mature detector, which is why PDR also rests on the CNN branch and on human review.</sub></p>

<p align="center"><img src="docs/img/quality.jpg" alt="Quality gate on five capture failures" width="100%"></p>
<p align="center"><sub>The quality gate on the same eye captured five ways: sharp → <b>GRADABLE</b> (0.97) · defocused → <b>RECAPTURE</b>, <i>“Out of focus: clean the lens, ask the patient to keep still, refocus on the vessels at the disc.”</i> · under-exposed → <b>ENHANCE</b> (enhanced and re-assessed; a person sees it if it is still not clean), <i>“Too dark: dim the room lights, let the pupil enlarge, or increase the flash.”</i> · lid and lashes → <b>RECAPTURE</b> · corneal flare with haze → <b>RECAPTURE</b>, <i>“Shadow or reflection at the edge: ask the patient to open the eye wide and hold the camera steady.”</i> Every message also exists in Hindi.</sub></p>

## Quick start

```matlab
>> netrasetu_setup                              % paths; reports which toolboxes are present
>> demo_netrasetu                               % 5-minute tour on synthetic eyes, no data needed
>> matlab_smoke                                 % 5-minute check of every MATLAB-only branch
>> R = netra.screen('eye.jpg');                 % one photograph, end to end
>> netra.xai.reportHTML(R, 'report.html');      % bilingual report
>> netra.ui.ScreeningApp                        % open a photo, check it, save the report (MATLAB)
>> netra.ui.ReaderConsole.demo()                % 30-second review (MATLAB)
>> run simulink/build_netrasetu_model           % build, run and check the Simulink model
>> run experiments/run_all                      % validation on the four datasets -> dossier
```

In GNU Octave (8.4 with the `image` and `statistics` packages) everything runs
except the CNN, the lesion ensemble, the two apps and Simulink itself —
the grader is then the calibrated rule engine, and the Simulink model's block
code is executed by an emulator. `tests/run_tests` runs the test suite in either.

## Measured here

These results were produced in this repository with GNU Octave 8.4 — on
synthetic data with exact ground truth, or against independent reference
implementations. They verify the engineering, not the clinical accuracy.

| What | Result |
|---|---|
| Test suite (`tests/run_tests`) | **50 / 50 passing** in GNU Octave 8.4 (and on every push, via GitHub Actions) — statistics, dataset readers, grading, explanation, simulation, end-to-end pipeline |
| Statistics vs independent implementations | ROC AUC, average precision, Brier score, quadratic weighted kappa = scikit-learn to 1e-12; Wilson interval and exact McNemar = statsmodels to 1e-12; proportional-odds model = statsmodels `OrderedModel` (max. likelihood) to 2e-4; DeLong SE and paired p = midrank reference (Sun & Xu) to 1e-7 |
| Microaneurysm localisation | RMS centre error **0.15 px at SNR 8 and 0.04 px at SNR 30 — on the Cramér–Rao bound** (0.14 and 0.04 px); the brightest pixel is 0.71 / 0.44 px off and a half-maximum centroid 0.18 / 0.10 px. Below SNR ≈ 6 a fit can lock onto noise, which is why the detector also demands contrast against the local texture |
| Simulink model vs MATLAB reference | the model's block code, run by the block emulator for a simulated year (8,736 hourly steps): **bit-identical** on all 14 logged signals at every step and all 48 KPIs, edge and cloud grading. Simulink itself was not available here: building and running the `.slx` is the first thing to do in MATLAB (`simulink/build_netrasetu_model`, which repeats this cross-check) |
| End-to-end on synthetic eyes | healthy eye not referred, severe NPDR referred, defocused photograph sent for recapture; disc within 0.25 DD and fovea within 0.5 DD on healthy and diseased eyes; the grade-4 phantom is referred but not flagged urgent (see above) |
| Screening in the browser | `docs/engine.js` ports the classical pipeline (quality gate, enhancement, vessels, disc, fovea, microaneurysms with the sub-pixel fit, haemorrhages, exudates, neovascularisation, the probabilistic ICDR rules, triage and the lesion evidence map) to JavaScript, with `netra.config`'s parameters; it runs in a Web Worker and the photo never leaves the device. Venous beading and IRMA stay in MATLAB. On the five practice eyes it gives the MATLAB triage (routine, routine, refer, refer, refer; grade 4 referred but not flagged urgent, as above), and on the five capture failures the MATLAB quality decisions. The trained CNN and lesion ensemble are not ported, so the browser grade rests on the rule engine, as `netra.screen` does without trained models. About 6 to 10 s per photo on a laptop |
| District model in the browser | `docs/sim.js` ports `netra.sim` line by line to JavaScript. With its own random stream it reproduces the optimiser's plan below within sampling noise: 102,717 vs 102,400 screens, ₹0.685 vs ₹0.68 crore, grader load 14.5 vs 14 %, ophthalmologist 60.9 vs 61 %, 4,698 vs 4,684 patients reaching treatment; plain review and cloud grading agree the same way |

<p align="center"><img src="docs/img/subpixel.png" alt="Microaneurysm localisation error versus signal-to-noise ratio" width="70%"></p>

## Validation on real data — run it yourself

`experiments/run_all.m` runs six experiments; each caches per-image results and
resumes, and `netra.eval.dossier` turns them into
`results/validation_dossier.html`.

| Experiment | Data | Question | Headline statistics |
|---|---|---|---|
| `exp01_vessels_drive` | DRIVE | Does fusing the three vessel detectors beat each alone? | pixel AUC, Se/Sp/Acc at a training-set threshold, paired bootstrap + sign test, second observer |
| `exp02_lesions_idrid` | IDRiD | How well are lesions, disc and fovea found? | AUPR per lesion type at native resolution (challenge metric), MA FROC, disc Jaccard, landmark error in DD |
| `exp03_train_grader` | APTOS 2019 + IDRiD train | Train and calibrate every learned part | 4-2-1 re-fit, NV normative model, lesion ensemble, CNN, fusion of every branch combination, conformal and operating point |
| `exp04_validate_grading` | APTOS hold-out, IDRiD test, **Messidor-2** | Is Se > 0.90 and Sp > 0.85 for referable DR reached, and does integration beat each technique on the same eyes? | Se/Sp (Wilson CI) per image and per patient, intention to screen, AUC (DeLong), paired DeLong and McNemar vs every single technique, QWK, calibration, conformal coverage, STARD flow |
| `exp05_explainability` | IDRiD lesion masks | Do the explanations point at the lesions? | pointing game, energy on lesions, lift over a uniform map; reader-console timing |
| `exp06_district_simulation` | — (uses the exp04 ROC) | What does 100,000 screens a year take? | cheapest feasible plan, what-if runs, Simulink cross-check |

The published results the dossier puts next to yours — Gulshan et al. 2016,
IDx-DR (Abràmoff 2016, 2018), the Iowa Detection Program, Voets et al.'s
re-implementation, Gulshan et al. 2019 in Aravind and Sankara Nethralaya,
smartphone-based screening in Chennai and Mumbai, the APTOS 2019 winner, DRIVE
methods, the IDRiD challenge and the screening standards — are in
[`netra.eval.benchmarks`](src/+netra/+eval/benchmarks.m) with their sources;
entries transcribed with less certainty are flagged *verify*.

## The district, simulated

<p align="center"><img src="docs/img/dashboard.png" alt="District planning dashboard" width="100%"></p>

With the illustrative defaults in [`netra.sim.defaults`](src/+netra/+sim/defaults.m) — 36 PHCs
running diabetes clinics, links from 2G to fibre with outages, an optometrist
reading hub and a tele-ophthalmologist — the optimiser's cheapest plan that
meets every target over a full simulated year is: **grading on the PHC
laptops, 33 PHCs equipped, today's links, one grader and one ophthalmologist
hour per weekday**: 102,400 screens a year, 95 % of routine results within
44.5 h, urgent patients counselled on the spot, about 4,700 referable patients
reaching treatment, for **₹0.68 crore a year (≈ ₹66 per screen)**.

The same year, the same patients, the same outages, one choice changed:

| | grader load | ophthalmologist load | routine result, 95th percentile | referable patients reaching treatment |
|---|---|---|---|---|
| chosen plan | 14 % | 61 % | 44.5 h | 4,684 |
| review **without** the explainable console (150 s instead of 30 s a case) | 72 % | **100 %**, saturated | **over 10 days** | 4,177 |
| every image uploaded and graded **in the cloud** | 13 % | 55 % | **over 10 days**, stuck in the uplink | 3,473 |

Explanation is what makes one grader enough; edge grading is what makes 2G
enough and lets the patient hear the result before leaving the PHC. The
30-second review time is the design target the Reader Console measures, and
every number here is a planning estimate from stated, editable assumptions —
replace them with local data (`experiments/exp06_district_simulation.m`; with a
measured ROC from `exp04` the simulation uses your validated model). The same
model runs in the browser on the [live site](https://adarsh-s-007.github.io/NetraSetu/#district),
with a control for every decision the optimiser searches over.

<p align="center"><img src="docs/img/simulink_model.svg" alt="Structure of the Simulink model" width="100%"></p>
<p align="center"><sub>The Simulink model, drawn from the same description (<code>netra.sim.simulinkBlocks</code>) that <code>netra.sim.buildSimulink</code> builds the <code>.slx</code> from.</sub></p>

## Repository

```
netrasetu_setup.m        paths, toolbox report          demo_netrasetu.m   the tour
src/+netra/
  screen.m               the whole pipeline for one eye
  +quality/              aperture, quality gate, standardisation, enhancement
  +anatomy/              vessels, optic disc, fovea, ETDRS frame
  +lesions/              microaneurysms (sub-pixel), haemorrhages, exudates/CWS, NV, venous beading
  +grading/              ICDR rules, lesion ensemble, +cnn/, ordinal fusion, conformal, operating point, triage
  +xai/                  Grad-CAM(++), concordance, evidence map, overlay, A4 and HTML reports
  +ui/                   Screening App (open a photo, check it) · Reader Console
  +eval/                 ROC/DeLong/QWK/Wilson/McNemar/FROC/calibration, benchmarks, dossier
  +sim/                  district model: scenario, stages, KPIs, optimiser, Simulink builder + emulator
  +phantom/              synthetic fundus photographs with exact ground truth
  +io/                   APTOS, IDRiD, DRIVE, Messidor-2 readers
experiments/             exp01 ... exp06, run_all
simulink/                build_netrasetu_model.m (writes NetraSetuTelescreening.slx)
tests/                   run_tests.m + test_*.m (script tests; run in Octave too), matlab_smoke.m
docs/                    index.html + app.js (live site) · engine.js (the pipeline in JavaScript) · sim.js (district model) ·
                         case.js + img/case/ (preloaded sample) · METHODS · VALIDATION · CLINICAL_SAFETY · img/
data/  models/  results/ where datasets, trained components and outputs go (not committed)
```

**Requirements.** MATLAB R2023b or later with the Image Processing, Computer
Vision, Deep Learning, Statistics and Machine Learning toolboxes and Simulink
(a GPU for CNN training), or GNU Octave ≥ 8 with the `image` and `statistics`
packages for everything that does not need those toolboxes.

## Read more

* [`docs/METHODS.md`](docs/METHODS.md) — what every stage computes, and why
* [`docs/VALIDATION.md`](docs/VALIDATION.md) — the analysis plan the experiments implement
* [`docs/CLINICAL_SAFETY.md`](docs/CLINICAL_SAFETY.md) — intended use, hazards and controls
* [`data/README.md`](data/README.md) — getting the four datasets
* [`models/README.md`](models/README.md) — what training writes and what loads it

NetraSetu is research software, not a medical device. Every referral is
confirmed by a qualified grader or ophthalmologist, and prospective validation
with local graders is required before clinical use.

Photographs on the live site: *Task-shifting: fundus imaging is done by a
technician* (Aravind Eye Care System) and *Fundus examination inside a
screening van, India* (RD Ravindran), both from the
[Community Eye Health Journal](https://www.flickr.com/photos/communityeyehealth/)
under [CC BY-NC 2.0](https://creativecommons.org/licenses/by-nc/2.0/), recompressed
for the web (`docs/img/fundus-technician-aravind.jpg`, `docs/img/screening-van-india.jpg`).
