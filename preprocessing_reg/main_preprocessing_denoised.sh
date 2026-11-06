#!/bin/bash

# ============================================================================
# main_preprocessing_denoised.sh — STAGE 2, option B: DENOISED pipeline
#
# Input:  fMRIPrep output (stage 1), MNI152NLin6Asym 2 mm space, plus the
#         fMRIPrep confounds file (desc-confounds_timeseries.tsv)
# Steps:  1. find motion outliers (FD > 0.5 mm)
#         2. build the nuisance regressor matrix:
#              Friston 24 motion parameters + CSF + WM + one spike
#              regressor per motion outlier
#         3. nuisance regression (fsl_regfilt)
#         4. high-pass filter (0.01 Hz)
#         5. spatial smoothing (SUSAN, FWHM 3 mm) + brain mask
# Output: derivatives/data_preprocessed_full/sub-XX/ses-XX/
#           sub-XX_ses-XX_task-XX_space-MNI152NLin6Asym_res-2_desc-preprocessed_bold.nii.gz
#           sub-XX_ses-XX_task-XX_desc-confounds_used.tsv  (regressors used)
#
# Normally submitted by step02_preprocessing.sh, but can be run directly:
#   ./main_preprocessing_denoised.sh <sub> <ses> <task>
#   e.g. ./main_preprocessing_denoised.sh 01 01 restMoCo
#
# Requires: FSL, and a conda environment with python3, numpy and pandas
#           (neuroconda_2_0)
# ============================================================================

set -e  # Exit on error

# ============================================================================
# COMMAND-LINE ARGUMENTS
# ============================================================================
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <sub> <ses> <task>"
    echo "Example: $0 01 01 restMoCo"
    exit 1
fi

sub=$1
ses=$2
task=$3

module load fsl
module load conda
conda activate neuroconda_2_0

# ============================================================================
# INPUT FILES (fMRIPrep outputs) — built from the arguments
# ============================================================================
fmriprep_base="/imaging/correia/bv01/PMC_2025"
func_base="${fmriprep_base}/data_ses-${ses}/derivatives/fmriprep24/sub-${sub}/ses-${ses}/func"

# Exact file names (one run per task, so no run- entity)
func="${func_base}/sub-${sub}_ses-${ses}_task-${task}_space-MNI152NLin6Asym_res-2_desc-preproc_bold.nii.gz"
func_mask="${func_base}/sub-${sub}_ses-${ses}_task-${task}_space-MNI152NLin6Asym_res-2_desc-brain_mask.nii.gz"
func_confounds="${func_base}/sub-${sub}_ses-${ses}_task-${task}_desc-confounds_timeseries.tsv"

# Stop if any input is missing
if [[ ! -f "$func" ]]; then
    echo "ERROR: Functional file not found: $func"
    exit 1
fi

if [[ ! -f "$func_mask" ]]; then
    echo "ERROR: Brain mask not found: $func_mask"
    exit 1
fi

if [[ ! -f "$func_confounds" ]]; then
    echo "ERROR: Confounds file not found: $func_confounds"
    exit 1
fi

# Output directory
output_dir="/imaging/correia/bv01/PMC_2025/derivatives/data_preprocessed_full/sub-${sub}/ses-${ses}"
mkdir -p "$output_dir"

# Temporary working directory (unique per sub/ses/task; deleted at the end)
temp_dir="/imaging/correia/bv01/PMC_2025/derivatives/data_preprocessed_full/sub-${sub}/ses-${ses}/.temp_sub-${sub}_ses-${ses}_task-${task}"

mkdir -p "$temp_dir"
cd "$temp_dir"

# Repetition time (s)
TR=2.0

echo "=========================================="
echo "fMRI Post-Processing Pipeline"
echo "=========================================="
echo "Subject: $sub"
echo "Session: $ses"
echo "Task: $task"
echo "Input: $func"
echo "Mask: $func_mask"
echo "Confounds: $func_confounds"
echo "Output directory: $output_dir"
echo "Temp directory: $temp_dir"
echo ""

# ============================================================================
# STEP 1: MOTION OUTLIERS (FD > 0.5 mm)
# Saves the indices of high-motion volumes to outlier_indices.npy
# ============================================================================
echo "STEP 1: Creating motion outliers from framewise displacement..."

python3 -c "
import numpy as np
import pandas as pd

func_confounds = '$func_confounds'

# Load confounds
confounds_df = pd.read_csv(func_confounds, sep='\t')

# Extract framewise displacement (handle NaN values)
fd = confounds_df['framewise_displacement'].fillna(0).values

# Find outliers (FD > 0.5 mm)
fd_threshold = 0.5
outlier_indices = np.where(fd > fd_threshold)[0]

# Save outlier indices
np.save('outlier_indices.npy', outlier_indices)

n_outliers = len(outlier_indices)
print(f'Found {n_outliers} motion outliers (FD > {fd_threshold} mm)')
if n_outliers > 0:
    print(f'Outlier timepoints: {outlier_indices}')
"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to create motion outliers"
    exit 1
fi

echo "  ✓ Motion outliers identified"
echo ""

# ============================================================================
# STEP 2: NUISANCE REGRESSOR MATRIX
# Friston 24 (6 motion params + derivatives + squares) + CSF + WM
# + one binary spike regressor per motion outlier.
# Writes noise_regressors.txt (for FSL) and a copy with header to output_dir.
# ============================================================================
echo "STEP 2: Creating confounds regressors file..."

python3 -c "
import numpy as np
import pandas as pd

func_confounds = '$func_confounds'
output_dir = '$output_dir'
sub = '$sub'
ses = '$ses'
task = '$task'

# Load confounds
confounds_df = pd.read_csv(func_confounds, sep='\t')

# Friston 24 movement parameters
friston_24 = [
    'trans_x', 'trans_x_derivative1', 'trans_x_power2', 'trans_x_derivative1_power2',
    'trans_y', 'trans_y_derivative1', 'trans_y_power2', 'trans_y_derivative1_power2',
    'trans_z', 'trans_z_derivative1', 'trans_z_power2', 'trans_z_derivative1_power2',
    'rot_x', 'rot_x_derivative1', 'rot_x_power2', 'rot_x_derivative1_power2',
    'rot_y', 'rot_y_derivative1', 'rot_y_power2', 'rot_y_derivative1_power2',
    'rot_z', 'rot_z_derivative1', 'rot_z_power2', 'rot_z_derivative1_power2'
]

csf_wm = ['csf', 'white_matter']

# Load motion outlier indices
outlier_indices = np.load('outlier_indices.npy')

# Create confounds matrix
confounds_matrix = confounds_df[friston_24 + csf_wm].copy()

# Replace NaN values with 0 (important for first timepoint derivatives)
confounds_matrix = confounds_matrix.fillna(0)

# Add motion outliers as binary regressors
n_timepoints = len(confounds_matrix)
for i, outlier_idx in enumerate(outlier_indices):
    col_name = f'motion_outlier_{i:02d}'
    confounds_matrix[col_name] = 0
    confounds_matrix.loc[outlier_idx, col_name] = 1

# Save as text file for FSL (no header, tab-separated)
confounds_matrix.to_csv('noise_regressors.txt', sep='\t', index=False, header=False)

# Also save as TSV for reference (with header)
confounds_used_path = f'{output_dir}/sub-{sub}_ses-{ses}_task-{task}_desc-confounds_used.tsv'
confounds_matrix.to_csv(confounds_used_path, sep='\t', index=False)

print(f'Total regressors: {confounds_matrix.shape[1]}')
print(f'  - Friston 24: 24')
print(f'  - CSF + WM: 2')
print(f'  - Motion outliers (FD > 0.5mm): {len(outlier_indices)}')
print(f'Shape: {confounds_matrix.shape[0]} timepoints x {confounds_matrix.shape[1]} regressors')
print(f'Confounds saved to: {confounds_used_path}')
"

if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to create confounds regressors"
    exit 1
fi

echo "  ✓ Confounds regressors file created"
echo ""

# ============================================================================
# STEP 3: NUISANCE REGRESSION (fsl_regfilt)
# ============================================================================
echo "STEP 3: Performing nuisance regression..."

# Working copy of the fMRIPrep output
cp "$func" func_orig.nii.gz

# Regress out ALL columns of noise_regressors.txt:
# -f takes a comma-separated list of column indices, here "1,2,...,N"
n_regressors=$(awk '{print NF}' noise_regressors.txt | head -1)
filter_indices=$(seq 1 $n_regressors | tr '\n' ',' | sed 's/,$//')

echo "  Regressing out $n_regressors confounds..."
fsl_regfilt -i func_orig.nii.gz -d noise_regressors.txt -o func_nuisance.nii.gz -f $filter_indices

if [[ $? -ne 0 ]]; then
    echo "ERROR: Nuisance regression failed"
    exit 1
fi

echo "  ✓ Nuisance regression complete"
echo ""

# ============================================================================
# STEP 4: HIGH-PASS FILTERING (0.01 Hz)
# ============================================================================
echo "STEP 4: Applying high-pass filtering..."

# FSL -bptf takes sigma in volumes: sigma = 1 / (2 * TR * cutoff_Hz)
hp_freq=0.01
hp_sigma=$(echo "scale=6; 1 / (2 * $TR * $hp_freq)" | bc)

echo "  HP frequency: $hp_freq Hz"
echo "  HP sigma: $hp_sigma"

# Temporal mean (removed by -bptf, added back afterwards);
# -bptf <hp_sigma> <lp_sigma>: lp_sigma = -1 disables the low-pass part
fslmaths func_nuisance.nii.gz -Tmean tempMean.nii.gz
fslmaths func_nuisance.nii.gz -bptf $hp_sigma -1 -add tempMean.nii.gz func_hpf.nii.gz

if [[ $? -ne 0 ]]; then
    echo "ERROR: High-pass filtering failed"
    exit 1
fi

echo "  ✓ High-pass filtering complete"
echo ""

# ============================================================================
# STEP 5: SPATIAL SMOOTHING (SUSAN)
# ============================================================================
echo "STEP 5: Applying spatial smoothing..."

fwhm=3  # 1.5 x voxel size (2 mm) = 3 mm
sigma=$(echo "scale=6; $fwhm / 2.355" | bc)   # FWHM -> Gaussian sigma

echo "  FWHM: $fwhm mm"
echo "  Sigma: $sigma"

# Brightness threshold = 75% of median in-brain intensity (as in FSL FEAT)
median=$(fslstats func_hpf.nii.gz -k "$func_mask" -p 50)
bright_thr=$(echo "scale=6; $median * 0.75" | bc)

echo "  Median intensity: $median"
echo "  Brightness threshold: $bright_thr"

# Temporal mean image used as the USAN (edge) reference, and its threshold
fslmaths func_hpf.nii.gz -Tmean mean_func.nii.gz
median_usan=$(fslstats mean_func.nii.gz -k "$func_mask" -p 50)
bright_thr_usan=$(echo "scale=6; $median_usan * 0.75" | bc)

# SUSAN: edge-preserving smoothing
#   args: <in> <bt> <sigma> <dim=3D> <use_median=1> <n_usans=1> <usan> <usan_bt> <out>
# then re-apply the brain mask to remove signal smoothed outside the brain
susan func_hpf.nii.gz $bright_thr $sigma 3 1 1 mean_func.nii.gz $bright_thr_usan func_smooth.nii.gz
fslmaths func_smooth.nii.gz -mas "$func_mask" func_smooth_masked.nii.gz

if [[ $? -ne 0 ]]; then
    echo "ERROR: Spatial smoothing failed"
    exit 1
fi

echo "  ✓ Spatial smoothing complete"
echo ""

# ============================================================================
# STEP 6: SAVE FINAL OUTPUT
# ============================================================================
echo "STEP 6: Saving outputs..."

final_output="${output_dir}/sub-${sub}_ses-${ses}_task-${task}_space-MNI152NLin6Asym_res-2_desc-preprocessed_bold.nii.gz"
cp func_smooth_masked.nii.gz "$final_output"

echo "  ✓ Final output saved: $final_output"
echo ""

# ============================================================================
# STEP 7: CLEANUP (delete temporary directory)
# ============================================================================
echo "Cleaning up temporary directory..."
cd /
rm -rf "$temp_dir"

echo "  ✓ Cleanup complete"
echo ""

echo "=========================================="
echo "Pipeline complete!"
echo "=========================================="
