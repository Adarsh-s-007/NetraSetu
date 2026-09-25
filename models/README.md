# Trained components

Nothing here is committed (`*.mat` is ignored): every file is produced on your
machine by the experiments, from data you are licensed to use. `netra.loadModels`
picks up whatever exists, and every missing component switches off cleanly -
the report then states which components produced the grade.

| File | Variable | Written by | What it is | Needs |
|---|---|---|---|---|
| `vessel_fusion.mat` | `model` | `exp01` | logistic fusion of the three vessel detectors, learned on DRIVE | any |
| `nv_normative.mat` | `normative` | `exp03` step 1 | median and spread of fine-vessel texture in grade-0 eyes, per zone | any |
| `lesion_model.mat` | `model` | `exp03` step 4 | bagged trees on 32 named lesion features, with out-of-fold posteriors and Shapley explanations | Statistics and Machine Learning Toolbox |
| `netrasetu_cnn.mat` | `model` | `exp03` step 5 | ImageNet backbone (ResNet-50 default) fine-tuned with the ordinal-cost loss, softmax temperature | Deep Learning Toolbox, R2023b+ (GPU advised) |
| `fusion.mat` | `fusion`, `variants` | `exp03` step 6 | proportional-odds stacking of the branches, and one model per branch combination (the ablation) | any |
| `calibration.mat` | `calibration` | `exp03` step 7 | conformal quantile, referral operating point with a Wilson-guaranteed sensitivity, re-fitted 4-2-1 rule, operating points of every ablation variant | any |

Under GNU Octave the lesion ensemble and the CNN are skipped; the grader is
then the calibrated rule engine (probabilistic ICDR rules + ordinal fusion +
conformal sets), which is fully transparent but has not been shown to reach
the clinical target on its own.

Keep several trained sets apart with the environment variable
`NETRA_MODELS=/path/to/models` (and `NETRA_RESULTS` for results).

**Provenance.** `calibration.mat` records the number of calibration eyes and
the creation date; reports and the validation dossier print which files were
loaded. Retrain and recalibrate when the camera, the population or the
grading protocol changes.
