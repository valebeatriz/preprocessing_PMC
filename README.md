# PMC_2025 — fMRI preprocessing

Preprocessing scripts for resting-state fMRI (prospective motion correction study, older and younger adults), run on a SLURM cluster.

## Pipeline

The pipeline always starts with **fMRIPrep**, then continues with **one** of two options:

```
                      ┌─► minimal  : high-pass filter → smoothing
 Stage 1: fMRIPrep ───┤
                      └─► denoised : nuisance regression → high-pass filter → smoothing
```

- **High-pass filter:** 0.01 Hz (`fslmaths -bptf`), TR = 2 s
- **Smoothing:** SUSAN, FWHM 3 mm
- **Nuisance regression (denoised only):** Friston 24 + CSF + WM + spike regressors for FD > 0.5 mm (`fsl_regfilt`)

Outputs go to `derivatives/data_preprocessed_minimal/` or `derivatives/data_preprocessed_full/`.

## Scripts

| Script | Purpose |
|---|---|
| `step01_fmriprep.sh` | Submits one fMRIPrep job per subject |
| `fmriprep_script.sh` | Runs fMRIPrep 24.1.1 (Apptainer) for one subject |
| `step02_preprocessing.sh` | Submits stage 2 jobs per subject × session × task |
| `preprocessing_reg/main_preprocessing_minimal.sh` | Minimal pipeline |
| `preprocessing_reg/main_preprocessing_denoised.sh` | Denoised pipeline |

## Usage

**Stage 1 — fMRIPrep**
1. In `step01_fmriprep.sh`, set the subjects to run
2. In `fmriprep_script.sh`
3. Run `./step01_fmriprep.sh`

**Stage 2 — minimal or denoised**
1. In `step02_preprocessing.sh`, choose the pipeline by (un)commenting the `CHOOSE PIPELINE` lines
2. Run `./step02_preprocessing.sh`

Paths are set to `/imaging/correia/bv01/PMC_2025` — edit them for your setup.

## Requirements

- SLURM
- Apptainer + fMRIPrep 24.1.1 image
- FreeSurfer license
- FSL
- Python 3