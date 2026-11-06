#!/bin/bash

#==============================================================================
# step02_preprocessing.sh — STAGE 2: post-fMRIPrep preprocessing (SLURM batch)
#==============================================================================
# Run this AFTER stage 1 (fMRIPrep) has finished.
#
# Submits one SLURM job per subject × session × task. All jobs run in
# parallel (no dependencies). Combinations whose fMRIPrep output is missing
# are skipped.
#
# Choose ONE of the two pipelines by (un)commenting the lines marked
# "CHOOSE PIPELINE" below — both main_script and log_dir must be switched:
#
#   minimal  -> preprocessing_reg/main_preprocessing_minimal.sh
#               high-pass filter + spatial smoothing (no nuisance regression)
#               output: derivatives/data_preprocessed_minimal/
#
#   denoised -> preprocessing_reg/main_preprocessing_denoised.sh
#               nuisance regression + high-pass filter + spatial smoothing
#               output: derivatives/data_preprocessed_full/
#
# Usage:  ./step02_preprocessing.sh
#==============================================================================

# CHOOSE PIPELINE: path to the main preprocessing script
#main_script="/imaging/correia/bv01/PMC_2025/code/preprocessing_reg/main_preprocessing_denoised.sh" #CHANGE HERE
main_script="/imaging/correia/bv01/PMC_2025/code/preprocessing_reg/main_preprocessing_minimal.sh"

# Project root (fMRIPrep outputs are under data_ses-XX/derivatives/fmriprep24)
fmriprep_base="/imaging/correia/bv01/PMC_2025"

# CHOOSE PIPELINE: SLURM log directory (keep matched to main_script above)
#log_dir="/imaging/correia/bv01/PMC_2025/scratch/preprocessing_logs" #CHANGE HERE
log_dir="/imaging/correia/bv01/PMC_2025/scratch/preprocessing_minimal_logs"

mkdir -p "$log_dir"

#------------------------------------------------------------------------------
# SLURM PARAMETERS
#------------------------------------------------------------------------------

TIME="04:00:00"             # Time limit per job (4 hours)
CPUS=8                      # Number of CPUs per job
MEM="16G"                   # Memory per job

#------------------------------------------------------------------------------
# SUBJECTS, SESSIONS AND TASKS TO PROCESS
#------------------------------------------------------------------------------

# Subjects 01 to 40, zero-padded (sub-01–20 older adults, sub-21–40 younger adults)
subjects=($(seq -f "%02g" 1 40))

# Sessions
sessions=("01" "02")

# Tasks = resting-state runs under three motion-correction conditions:
#   restMoCo   - PMC ON, Marker ON (prospective motion correction)
#   restNoMoCo - PMC OFF, Marker ON 
#   restNoMark - PMC OFF, Marker OFF 
tasks=("restMoCo" "restNoMoCo" "restNoMark")

#------------------------------------------------------------------------------
# OPTIONAL: override with a smaller set (uncomment to use)
#------------------------------------------------------------------------------

# # Example: process only subjects 01-02, session 01, task restMoCo
# subjects=($(seq -f "%02g" 1 2))
# sessions=("01")
# tasks=("restMoCo")

#------------------------------------------------------------------------------
# SUBMIT ONE JOB PER SUBJECT / SESSION / TASK
#------------------------------------------------------------------------------

echo "======================================================================"
echo "Batch Preprocessing Started (PARALLEL):  $(date)"
echo "======================================================================"
echo "Subjects: ${#subjects[@]} (${subjects[0]} - ${subjects[-1]})"
echo "Sessions: ${#sessions[@]} (${sessions[*]})"
echo "Tasks: ${#tasks[@]} (${tasks[*]})"
echo "Total jobs: $((${#subjects[@]} * ${#sessions[@]} * ${#tasks[@]}))"
echo "======================================================================"
echo ""

# Counters
total_jobs=$((${#subjects[@]} * ${#sessions[@]} * ${#tasks[@]}))
current_job=0
submitted=0
skipped=0

for sub in "${subjects[@]}"; do
  for ses in "${sessions[@]}"; do
    for task in "${tasks[@]}"; do
      
      current_job=$((current_job + 1))
      
      # fMRIPrep output for this combination (single run per task)
      func="${fmriprep_base}/data_ses-${ses}/derivatives/fmriprep24/sub-${sub}/ses-${ses}/func/sub-${sub}_ses-${ses}_task-${task}_space-MNI152NLin6Asym_res-2_desc-preproc_bold.nii.gz"
      
      # Skip if fMRIPrep output does not exist
      if [[ ! -f "$func" ]]; then
        echo "[$current_job/$total_jobs] SKIP: sub-${sub} ses-${ses} task-${task} (file not found)"
        skipped=$((skipped + 1))
        continue
      fi
      
      echo "[$current_job/$total_jobs] Submitting: sub-${sub} ses-${ses} task-${task}"
      
      # One log file per job (stdout and stderr together)
      log_file="${log_dir}/sub-${sub}_ses-${ses}_task-${task}_$(date +%Y%m%d_%H%M%S).log"
      
      # Build sbatch command (no dependencies: all jobs run in parallel)
      sbatch_cmd="sbatch"
      sbatch_cmd="$sbatch_cmd --job-name=pp_${sub}_${ses}_${task:0:4}"
      sbatch_cmd="$sbatch_cmd --output=${log_file}"
      sbatch_cmd="$sbatch_cmd --error=${log_file}"
      sbatch_cmd="$sbatch_cmd --time=${TIME}"
      sbatch_cmd="$sbatch_cmd --cpus-per-task=${CPUS}"
      sbatch_cmd="$sbatch_cmd --mem=${MEM}"
      
      # Submit: runs the chosen main script with <sub> <ses> <task>
      job_id=$($sbatch_cmd --parsable --wrap="bash $main_script $sub $ses $task")
      
      if [[ -n "$job_id" ]]; then
        echo "  ✓ Job ID: $job_id"
        echo "  Log: ${log_file}"
        submitted=$((submitted + 1))
      else
        echo "  ✗ Failed to submit job"
        skipped=$((skipped + 1))
      fi
      
      # Small delay to avoid overwhelming the scheduler
      sleep 1
      
    done
  done
done

#------------------------------------------------------------------------------
# FINAL SUMMARY
#------------------------------------------------------------------------------

echo ""
echo "======================================================================"
echo "Batch Job Submission Completed:  $(date)"
echo "======================================================================"
echo "Total jobs: $total_jobs"
echo "Submitted: $submitted"
echo "Skipped: $skipped"
echo "Log directory: $log_dir"
echo "======================================================================"
