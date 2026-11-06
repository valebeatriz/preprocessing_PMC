#!/bin/bash

#=============================================================================
# step01_fmriprep.sh — STAGE 1: submit fMRIPrep jobs to SLURM
#
# For each subject folder matched by the loop below, submits one SLURM job
# that runs fmriprep_script.sh for that subject.
#
# Always run this stage first. Once fMRIPrep has finished, run stage 2
# (step02_preprocessing.sh) with either the minimal or the denoised pipeline.
#
# Usage:
#   1. Set PROJECT_PATH and SCRIPT_PATH below.
#   2. Edit the subject/session pattern in the loop at the bottom.
#   3. Run:  ./step01_fmriprep.sh
#
# =============================================================================

# ------------------------------------------------------------
#
# !FILL IN THE VARIABLES BELOW!
#
# ------------------------------------------------------------

# Project root directory (contains data_ses-01/, data_ses-02/, code/, scratch/)
PROJECT_PATH='/imaging/correia/bv01/PMC_2025'

# Location of the per-subject fMRIPrep script
SCRIPT_PATH="$PROJECT_PATH"/code/fmriprep_script.sh

# ------------------------------------------------------------
#
# Nothing below needs changing, except the subject/session
# pattern in the submission loop.
#
# ------------------------------------------------------------

# ------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------
echo "Checking if the project directory exists..."
if [ ! -d "$PROJECT_PATH" ]; then
    echo "Project directory does not exist: $PROJECT_PATH"
    exit 1
fi

echo "Checking if the fmriprep_script.sh exists..."
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "The script $SCRIPT_PATH does not exist"
    exit 1
fi

#-----------------------------------------------------------
# SLURM job logs are written here
#-----------------------------------------------------------
JOB_DIR="$PROJECT_PATH"/scratch/fmriprep_24/job_logs
mkdir -p "$JOB_DIR"
cd "$JOB_DIR" || exit

#-----------------------------------------------------------
# Submit one fMRIPrep job per subject, 1 minute apart
#
# EDIT THE PATTERN BELOW to choose which subjects/session to run:
#   one subject:   "$PROJECT_PATH"/data_ses-02/sub-20/
#   all subjects:  "$PROJECT_PATH"/data_ses-02/sub-*/
# The session here must match the session hard-coded in fmriprep_script.sh.
#-----------------------------------------------------------
for d in "$PROJECT_PATH"/data_ses-02/sub-20/; do
    sid=$(basename "$d")    
    echo "Submitting job for subject: ${sid}"
    sbatch \
        --job-name=fmriprep \
        --time=7-00:00 \
        --cpus-per-task=8 \
        "$SCRIPT_PATH" "${PROJECT_PATH}" "${sid}"

    sleep 1m   # Stagger jobs: workaround for running fMRIPrep subjects in parallel https://neurostars.org/t/updated-fmriprep-workaround-for-running-subjects-in-parallel/6677
done
