#!/bin/sh

# ============================================================
# fmriprep_script.sh — runs fMRIPrep for ONE subject
#
# STAGE 1 of the pipeline (see README.md).
#
# This script is not meant to be run directly: it is submitted to SLURM
# by step01_fmriprep.sh, which passes the project path and subject ID.
# To run it on its own, call it with the two arguments below, e.g.:
#   sbatch fmriprep_script.sh /path/to/project sub-01
#
# fMRIPrep is run from an Apptainer (Singularity) image.
# To get a newer image use:
#   docker pull nipreps/fmriprep:<latest-version>
#   (or build a .sif from it with apptainer/singularity)
#
# Outputs (used by stage 2, step02_preprocessing.sh):
#   <PROJECT_PATH>/data_ses-02/derivatives/fmriprep24/sub-XX/...
#   with BOLD data in MNI152NLin6Asym (2 mm), T1w and native func space.
#
# NOTE: the input/output folders below are set to session 02
# (data_ses-02). Change them to data_ses-01 to process session 01.
# ============================================================


#-----------------------------------------------------------
# Arguments passed in by step01_fmriprep.sh
#   $1 = project root directory
#   $2 = subject label (e.g. sub-20)
#-----------------------------------------------------------
PROJECT_PATH=${1}
subject=${2}

#-----------------------------------------------------------
# Log start time and subject to the job output
#-----------------------------------------------------------
start=$(date +%s)
date
echo Submitted subject: "$subject"

# ======================================================================
# Run fMRIPrep with Apptainer (Singularity)
# ======================================================================

# Initialise the environment-modules system so `module load` works
if [ -f /etc/profile.d/modules.sh ]; then
  . /etc/profile.d/modules.sh
else
  echo "Modules initialization script not found."
  exit 1
fi

# Load the apptainer module
module load apptainer

# fMRIPrep arguments (full list: https://fmriprep.org/en/stable/usage.html)
#   -B                      bind the project folder to /MyProject inside the container
#   positional args         BIDS input dir, output (derivatives) dir, analysis level
#   --fs-license-file       FreeSurfer license (not included in this repository)
#   --work-dir              intermediate files; can be deleted after a successful run
#   --participant-label     subject to process
#   --output-spaces         MNI152NLin6Asym at 2 mm (used downstream), plus T1w and native func
#   --nthreads/--omp-nthreads  CPU usage
#   --stop-on-first-crash   abort immediately if any step fails

apptainer run \
    -B "$PROJECT_PATH":/MyProject \
    /imaging/local/software/singularity_images/fmriprep/fmriprep-24.1.1.sif \
    /MyProject/data_ses-02 \
    /MyProject/data_ses-02/derivatives/fmriprep24\
    participant \
    --fs-license-file /MyProject/code/freesurfer_license.txt \
    --work-dir /MyProject/scratch/fmriprep_24_ses-02 \
    --participant-label "$subject" \
    --output-spaces MNI152NLin6Asym:res-2 T1w func \
    --nthreads 16 --omp-nthreads 8 \
    --stop-on-first-crash 


# Unload the apptainer module
module unload apptainer

#-----------------------------------------------------------
# Log total run time to the job output
#-----------------------------------------------------------
end=$(date +%s)
echo Time elapsed: "$(TZ=UTC0 printf '%(%H:%M:%S)T\n' $((end - start)))"
