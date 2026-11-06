#!/bin/bash

# ============================================================================
# main_preprocessing_minimal.sh — STAGE 2, option A: MINIMAL pipeline
#
# Input:  fMRIPrep output (stage 1), MNI152NLin6Asym 2 mm space
# Steps:  1. working copy
#         2. high-pass filter (0.01 Hz)
#         3. spatial smoothing (SUSAN, FWHM 3 mm) + brain mask
#         (NO nuisance regression — see main_preprocessing_denoised.sh for that)
# Output: derivatives/data_preprocessed_minimal/sub-XX/ses-XX/
#           sub-XX_ses-XX_task-XX_space-MNI152NLin6Asym_res-2_desc-preprocessed_bold.nii.gz
#
# Normally submitted by step02_preprocessing.sh, but can be run directly:
#   ./main_preprocessing_minimal.sh <sub> <ses> <task>
#   e.g. ./main_preprocessing_minimal.sh 01 01 restMoCo
#
# Requires: FSL, and a conda environment with python3 (neuroconda_2_0)
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

# Stop if any input is missing
if [[ ! -f "$func" ]]; then
    echo "ERROR: Functional file not found: $func"
    exit 1
fi

if [[ ! -f "$func_mask" ]]; then
    echo "ERROR: Brain mask not found: $func_mask"
    exit 1
fi

# Output directory
output_dir="/imaging/correia/bv01/PMC_2025/derivatives/data_preprocessed_minimal/sub-${sub}/ses-${ses}"
mkdir -p "$output_dir"

# Temporary working directory (unique per sub/ses/task; deleted at the end)
temp_dir="/imaging/correia/bv01/PMC_2025/derivatives/data_preprocessed_minimal/sub-${sub}/ses-${ses}/.temp_sub-${sub}_ses-${ses}_task-${task}"

mkdir -p "$temp_dir"
cd "$temp_dir"

# Repetition time (s)
TR=2.0

echo "=========================================="
echo "fMRI Minimal Preprocessing Pipeline"
echo "=========================================="
echo "Subject: $sub"
echo "Session: $ses"
echo "Task: $task"
echo "Input: $func"
echo "Mask: $func_mask"
echo "Output directory: $output_dir"
echo "Temp directory: $temp_dir"
echo "Processing: HIGH-PASS FILTERING + SPATIAL SMOOTHING (NO nuisance regression)"
echo ""

# ============================================================================
# STEP 1: WORKING COPY OF fMRIPrep OUTPUT
# ============================================================================
echo "STEP 1: Creating working copy of preprocessed data..."

cp "$func" func_orig.nii.gz

echo "  ✓ Working copy created"
echo ""

# ============================================================================
# STEP 2: HIGH-PASS FILTERING (0.01 Hz)
# ============================================================================
echo "STEP 2: Applying high-pass filtering..."

# FSL -bptf takes sigma in volumes: sigma = 1 / (2 * TR * cutoff_Hz)
hp_freq=0.01
hp_sigma=$(echo "scale=6; 1 / (2 * $TR * $hp_freq)" | bc)

echo "  HP frequency: $hp_freq Hz"
echo "  HP sigma: $hp_sigma"

# Temporal mean (removed by -bptf, added back afterwards)
fslmaths func_orig.nii.gz -Tmean tempMean.nii.gz

# -bptf <hp_sigma> <lp_sigma>: lp_sigma = -1 disables the low-pass part
fslmaths func_orig.nii.gz -bptf $hp_sigma -1 -add tempMean.nii.gz func_hpf.nii.gz

if [[ $? -ne 0 ]]; then
    echo "ERROR: High-pass filtering failed"
    exit 1
fi

echo "  ✓ High-pass filtering complete"
echo ""

# ============================================================================
# STEP 3: SPATIAL SMOOTHING (SUSAN)
# ============================================================================
echo "STEP 3: Applying spatial smoothing..."

fwhm=3   # 1.5 x voxel size (2 mm) = 3 mm
sigma=$(echo "scale=6; $fwhm / 2.355" | bc)   # FWHM -> Gaussian sigma

echo "  FWHM: $fwhm mm"
echo "  Sigma: $sigma"

# Brightness threshold = 75% of median in-brain intensity (as in FSL FEAT)
median=$(fslstats func_hpf.nii.gz -k "$func_mask" -p 50)
bright_thr=$(echo "scale=6; $median * 0.75" | bc)

echo "  Median intensity: $median"
echo "  Brightness threshold: $bright_thr"

# Temporal mean image used as the USAN (edge) reference
fslmaths func_hpf.nii.gz -Tmean mean_func.nii.gz

# Brightness threshold for the USAN reference image
median_usan=$(fslstats mean_func.nii.gz -k "$func_mask" -p 50)
bright_thr_usan=$(echo "scale=6; $median_usan * 0.75" | bc)

# SUSAN: edge-preserving smoothing
#   args: <in> <bt> <sigma> <dim=3D> <use_median=1> <n_usans=1> <usan> <usan_bt> <out>
susan func_hpf.nii.gz $bright_thr $sigma 3 1 1 mean_func.nii.gz $bright_thr_usan func_smooth.nii.gz

# Re-apply brain mask to remove signal smoothed outside the brain
fslmaths func_smooth.nii.gz -mas "$func_mask" func_smooth_masked.nii.gz

if [[ $? -ne 0 ]]; then
    echo "ERROR: Spatial smoothing failed"
    exit 1
fi

echo "  ✓ Spatial smoothing complete"
echo ""

# ============================================================================
# STEP 4: SAVE FINAL OUTPUT
# ============================================================================
echo "STEP 4: Saving outputs..."

final_output="${output_dir}/sub-${sub}_ses-${ses}_task-${task}_space-MNI152NLin6Asym_res-2_desc-preprocessed_bold.nii.gz"

cp func_smooth_masked.nii.gz "$final_output"

echo "  ✓ Final output saved: $final_output"
echo ""

# ============================================================================
# STEP 5: CLEANUP (delete temporary directory)
# ============================================================================
echo "Cleaning up temporary directory..."
cd /
rm -rf "$temp_dir"

echo "  ✓ Cleanup complete"
echo ""

echo "=========================================="
echo "Pipeline complete!"
echo "=========================================="
