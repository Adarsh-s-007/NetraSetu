# Datasets

NetraSetu is validated on four public datasets. None of them may be
redistributed, so they are not in this repository: download each one from its
source, accept its licence, and unpack it here (or anywhere, and point the
environment variable `NETRA_DATA` at that folder).

```
data/
├── APTOS2019/        train.csv, train_images/<id_code>.png
├── IDRiD/            A. Segmentation/, B. Disease Grading/, C. Localization/
├── DRIVE/            training/{images,1st_manual,mask}, test/{images,1st_manual,2nd_manual,mask}
└── Messidor-2/       IMAGES/*, messidor_data.csv, messidor-2.csv
```

Folder names are matched loosely (`aptos2019-blindness-detection`, `idrid`,
`messidor2` all work) and the files inside are found by name, not by fixed
paths, so the layouts of the official archives work as unpacked. Check what
was found with, for example, `netra.io.describe(netra.io.idrid())`.

| Dataset | Used for | Images | Source |
|---|---|---|---|
| **APTOS 2019 Blindness Detection** | training, calibration, internal hold-out | 3,662 labelled (Aravind Eye Hospital, India) | <https://www.kaggle.com/c/aptos2019-blindness-detection> (Kaggle account, competition rules) |
| **IDRiD** | lesion masks, disc/fovea centres, grading (train + external test) | 81 segmentation, 516 grading, 516 localisation (Nanded, India) | <https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid> (CC BY 4.0) |
| **DRIVE** | vessel segmentation | 40 (20 train, 20 test) | <https://drive.grand-challenge.org/> (registration) |
| **Messidor-2** | external validation (France) | 1,748 images, 874 patients | <https://www.adcis.net/en/third-party/messidor2/> (licence agreement) |

## Notes per dataset

**APTOS 2019.** Only the Kaggle *train* set has labels. `exp03` splits it,
stratified by grade (seed 2026), into train / validation / fusion /
calibration / hold-out and saves the split to `results/exp03/splits.mat`.
APTOS has no patient identifiers and contains duplicate photographs, so its
hold-out is an optimistic, internal estimate; the external sets are the ones
that count.

**IDRiD.** Keep the three parts (`A. Segmentation`, `B. Disease Grading`,
`C. Localization`) side by side under one folder. Lesion masks are the
`.tif` files (`IDRiD_NN_MA/HE/EX/SE/OD.tif`); the grading CSVs keep their
original names. DME grade 2 (exudates within one disc diameter of the fovea)
counts as referable.

**DRIVE.** The grand-challenge release withholds the test labels; with that
release `exp01` trains on half of the training images and tests on the other
half and says so in its output. The original release includes the test
labels and the second observer.

**Messidor-2.** The images come from ADCIS without grades. The widely used
adjudicated grades (Krause et al., *Ophthalmology* 2018) are distributed as
`messidor_data.csv` (columns `image_id, adjudicated_dr_grade,
adjudicated_dme, adjudicated_gradable`); put it anywhere under the folder.
Export the ADCIS pairs spreadsheet as CSV (`messidor-2.csv`, one row per
examination naming its two images) to get per-patient results.

## Without the data

`tests/helpers/makeFakeDatasets.m` writes miniature versions of all four
trees from synthetic phantoms. They exercise the readers and every experiment
script end to end (a smoke test). They say nothing about clinical accuracy.
