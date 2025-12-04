#!/bin/bash

# Script to submit SLURM jobs for synthetic sample generation
# Submits seqkit subsampling jobs and provides instructions for aggregation

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find workspace root by searching upward for sentinel files
find_workspace_root() {
  local start_dir="${1:-$PWD}"
  local max_depth="${SMG_ROOT_MAX_DEPTH:-10}"
  local current_dir="${start_dir}"

  for ((depth = 0; depth < max_depth; depth++)); do
    if [[ -f "${current_dir}/.here" ]] || \
       [[ -d "${current_dir}/.git" ]] || \
       [[ -f "${current_dir}/pixi.lock" ]] || \
       [[ -f "${current_dir}/.env" ]]; then
      printf '%s\n' "${current_dir}"
      return 0
    fi

    if [[ "${current_dir}" == "/" ]]; then
      break
    fi
    current_dir="$(dirname "${current_dir}")"
  done

  return 1
}

# Auto-detect workspace root directory
ROOT_SEARCH_DEPTH="${SMG_ROOT_MAX_DEPTH:-10}"
PROJECT_DIR=$(find_workspace_root "${SCRIPT_DIR}")
if [[ -z "${PROJECT_DIR}" ]]; then
    echo "[ERROR] Could not detect workspace root directory after searching $ROOT_SEARCH_DEPTH levels up from ${SCRIPT_DIR}" >&2
    echo "[ERROR] Looking for: .here, .git, pixi.lock, or .env" >&2
    exit 1
fi

# Source logging helpers from project root
LOG_LIB="${PROJECT_DIR}/lib/sh/logging.sh"
if [[ -r "${LOG_LIB}" ]]; then
    # shellcheck disable=SC1090
    source "${LOG_LIB}"
else
    echo "[ERROR] Missing logging helpers at ${LOG_LIB}" >&2
    exit 1
fi

# Initialize timing variables
SCRIPT_START_TIME=$(date +%s)
SECONDS=0

log_step "SLURM Job Submission for Synthetic Sample Generation"
log_info "Script started at: $(date)"

# Load environment variables from .env file if it exists
ENV_FILE="${PROJECT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "${ENV_FILE}"
    set +a
    log_info "Loaded environment variables from ${ENV_FILE}"
fi

# Configuration - fixed paths
SYN_SPECS_DIR="$PROJECT_DIR/data/syn_specs_khroma"
LOGS_DIR="$PROJECT_DIR/slurm/logs/seqkit_subsampling"

# Available read count files
ALL_READ_COUNTS=("1e+04" "1e+05" "1e+06" "1e+07")

# Filter read counts if specified via environment variable or test mode
if [[ -n "${READ_COUNTS_FILTER:-}" ]]; then
    # Parse space or comma-separated list
    IFS=', ' read -ra FILTER_ARRAY <<< "${READ_COUNTS_FILTER}"
    READ_COUNTS=()
    for filter_val in "${FILTER_ARRAY[@]}"; do
        for rc in "${ALL_READ_COUNTS[@]}"; do
            if [[ "$rc" == "$filter_val" ]]; then
                READ_COUNTS+=("$rc")
                break
            fi
        done
    done
    if [[ ${#READ_COUNTS[@]} -eq 0 ]]; then
        log_error "No valid read counts found in READ_COUNTS_FILTER: ${READ_COUNTS_FILTER}"
        log_error "Available read counts: ${ALL_READ_COUNTS[*]}"
        exit 1
    fi
    log_info "Filtered read counts: ${READ_COUNTS[*]}"
elif [[ -n "${TEST_MODE:-}" ]]; then
    # Test mode: only process the first read count
    READ_COUNTS=("${ALL_READ_COUNTS[0]}")
    log_info "TEST_MODE enabled: processing only ${READ_COUNTS[0]} reads"
else
    READ_COUNTS=("${ALL_READ_COUNTS[@]}")
fi

# Create logs directory
mkdir -p "$LOGS_DIR"

log_info "Project structure validated"
log_info "  PROJECT_DIR: $PROJECT_DIR"
log_info "  SYN_SPECS_DIR: $SYN_SPECS_DIR"
log_info "  LOGS_DIR: $LOGS_DIR"

# Track all submitted job IDs for dependency management
ALL_JOB_IDS=()

for read_count in "${READ_COUNTS[@]}"; do
    log_info "Processing ${read_count} reads..."

    # Get the number of lines in the command file
    COMMAND_FILE="${SYN_SPECS_DIR}/seqkit_subsampling_specs_${read_count}.txt"

    if [ ! -f "$COMMAND_FILE" ]; then
        log_error "Command file not found: $COMMAND_FILE"
        log_error "Please run gen_syn_specs.R first to generate the specification files"
        continue
    fi

    ARRAY_SIZE=$(wc -l < "$COMMAND_FILE")

    # Limit array size in test mode
    if [[ -n "${TEST_MODE:-}" ]]; then
        TEST_ARRAY_SIZE="${TEST_ARRAY_SIZE:-1}"
        if [[ "$ARRAY_SIZE" -gt "$TEST_ARRAY_SIZE" ]]; then
            log_info "Test mode: limiting array size from ${ARRAY_SIZE} to ${TEST_ARRAY_SIZE} tasks"
            ARRAY_SIZE="$TEST_ARRAY_SIZE"
        fi
    fi

    # Create a temporary SLURM script with the correct array size
    TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << EOF
#!/bin/bash
#SBATCH --job-name=seqkit_${read_count}
#SBATCH --partition=normal
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --array=1-${ARRAY_SIZE}%10
#SBATCH --output=${LOGS_DIR}/log_${read_count}_%j.out
#SBATCH --error=${LOGS_DIR}/log_${read_count}_%j.err

# Parse command line arguments
READ_COUNT="${read_count}"
SEEDFILE="${COMMAND_FILE}"

# Check if the seedfile exists
if [ ! -f "\$SEEDFILE" ]; then
    echo "ERROR: Seed file \$SEEDFILE not found"
    exit 1
fi

SEED=\$(sed -n \${SLURM_ARRAY_TASK_ID}p \$SEEDFILE)

# change wd to the project directory
cd ${PROJECT_DIR}

# Create output directories if they don't exist
mkdir -p data/datasets/low_diversity/individual
mkdir -p data/datasets/mid_diversity/individual
mkdir -p data/datasets/high_diversity/individual

# Set directories
SOURCE_DIR="data/source_fastq"
OUTPUT_DIR="data/datasets"

# prep variables
IN=\`echo \$SEED | awk '{ print \$1 }'\`
INPUT_FILE="\${SOURCE_DIR}/\${IN}"
RNDSEED=\`echo \$SEED | awk '{ print \$2 }'\`
READS=\`echo \$SEED | awk '{ print \$3 }'\`
OUT=\`echo \$SEED | awk '{ print \$4 }'\`
OUTPUT_FILE="\${OUTPUT_DIR}/\${OUT}"

# Check if input file exists
if [ ! -f "\$INPUT_FILE" ]; then
    echo "ERROR: Input file \$INPUT_FILE not found"
    echo "Current directory: \$(pwd)"
    echo "Looking for: \$INPUT_FILE"
    exit 1
fi

# Create output directory if it doesn't exist (including parent directories)
OUTPUT_FILE_DIR=\$(dirname "\$OUTPUT_FILE")
mkdir -p "\$OUTPUT_FILE_DIR"

# Run seqkit command with memory monitoring
# Using pixi run to access seqkit from the pixi environment
# Use pipefail to catch failures in the pipeline
set -o pipefail
/usr/bin/time -f "Time: %E, CPU: %P, Memory: %M KB, Exit: %x" pixi run seqkit shuffle -s \$RNDSEED \$INPUT_FILE -o - | pixi run seqkit head -n \$READS -o \$OUTPUT_FILE
# Capture PIPESTATUS immediately (before any other command overwrites it)
PIPESTATUS_VALUES=("\${PIPESTATUS[@]}")
PIPESTATUS_SHUFFLE=\${PIPESTATUS_VALUES[0]}
PIPESTATUS_HEAD=\${PIPESTATUS_VALUES[1]}

# Derive overall exit code from PIPESTATUS
# (with pipefail: rightmost non-zero, or 0 if all succeeded)
if [ \$PIPESTATUS_HEAD -ne 0 ]; then
    EXIT_CODE=\$PIPESTATUS_HEAD
elif [ \$PIPESTATUS_SHUFFLE -ne 0 ]; then
    EXIT_CODE=\$PIPESTATUS_SHUFFLE
else
    EXIT_CODE=0
fi

# Verify output file even if command exited with non-zero code
# (seqkit may exit with code 1 for non-critical reasons
# and still produce valid output)
# Note: Due to known issues with seqkit/pixi exit codes
# (seqkit#555, pixi#5016), we rely on output file validity
# rather than exit codes for success determination
if [ -f "\$OUTPUT_FILE" ]; then
    # Check if the file is valid gzip
    if gzip -t "\$OUTPUT_FILE" 2>/dev/null; then
        echo "Processed: \$INPUT_FILE -> \$OUTPUT_FILE (reads: \$READS, seed: \$RNDSEED)"
        echo -n "Pipeline exit codes [shuffle, head]: "
        echo "[\$PIPESTATUS_SHUFFLE, \$PIPESTATUS_HEAD] (overall: \$EXIT_CODE)"
        exit 0
    else
        echo "ERROR: Output file exists but is corrupted: \$OUTPUT_FILE"
        echo -n "Pipeline exit codes [shuffle, head]: "
        echo "[\$PIPESTATUS_SHUFFLE, \$PIPESTATUS_HEAD] (overall: \$EXIT_CODE)"
        rm -f "\$OUTPUT_FILE"
        exit 1
    fi
elif [ \$EXIT_CODE -eq 0 ]; then
    echo "ERROR: Command succeeded but output file not found: \$OUTPUT_FILE"
    echo -n "Pipeline exit codes [shuffle, head]: "
    echo "[\$PIPESTATUS_SHUFFLE, \$PIPESTATUS_HEAD] (overall: \$EXIT_CODE)"
    exit 1
else
    echo "ERROR: Failed to process \$INPUT_FILE -> \$OUTPUT_FILE (exit code: \$EXIT_CODE)"
    echo -n "Pipeline exit codes [shuffle, head]: "
    echo "[\$PIPESTATUS_SHUFFLE, \$PIPESTATUS_HEAD] (overall: \$EXIT_CODE)"
    exit \$EXIT_CODE
fi
EOF

    # Submit the job
    SBATCH_OUTPUT=$(sbatch "$TEMP_SCRIPT" 2>&1)
    SBATCH_EXIT_CODE=$?

    if [ $SBATCH_EXIT_CODE -eq 0 ]; then
        JOB_ID=$(echo "$SBATCH_OUTPUT" | awk '{print $4}')
        if [[ -n "$JOB_ID" && "$JOB_ID" =~ ^[0-9]+$ ]]; then
            log_info "Submitted job ${JOB_ID} for ${read_count} reads (${ARRAY_SIZE} tasks)"
            ALL_JOB_IDS+=("$JOB_ID")
        else
            log_error "Failed to parse job ID from sbatch output"
            log_error "sbatch output: $SBATCH_OUTPUT"
        fi
    else
        log_error "Failed to submit job for ${read_count} reads"
        log_error "sbatch output: $SBATCH_OUTPUT"
    fi

    # Clean up temporary script
    rm -f "$TEMP_SCRIPT"
done

TOTAL_ELAPSED=$(( $(date +%s) - SCRIPT_START_TIME ))

# Skip aggregation job in test mode
if [[ -z "${TEST_MODE:-}" ]]; then
    log_step "Submitting aggregation job"
    log_info "All seqkit jobs submitted. Submitting aggregation job that depends on all seqkit jobs..."

# Build dependency string if we have job IDs
DEPENDENCY_LINE=""
if [ ${#ALL_JOB_IDS[@]} -gt 0 ]; then
    # Create dependency string: afterok:job1:job2:job3...
    DEPENDENCY="afterok"
    for job_id in "${ALL_JOB_IDS[@]}"; do
        DEPENDENCY="${DEPENDENCY}:${job_id}"
    done
    DEPENDENCY_LINE="#SBATCH --dependency=${DEPENDENCY}"
fi

# Create aggregation job script
AGG_TEMP_SCRIPT=$(mktemp)
cat > "$AGG_TEMP_SCRIPT" << EOF
#!/bin/bash
#SBATCH --job-name=agg_syn_samples
#SBATCH --partition=normal
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --output=${LOGS_DIR}/agg_syn_samples_%A_%04a.out
#SBATCH --error=${LOGS_DIR}/agg_syn_samples_%A_%04a.err
${DEPENDENCY_LINE}

# Change to project directory
cd ${PROJECT_DIR}

# Run aggregation script
AGG_SCRIPT="tools/gen_agg_syn_datasets.sh"
if [ ! -f "\$AGG_SCRIPT" ]; then
    echo "ERROR: Aggregation script not found: \$AGG_SCRIPT"
    exit 1
fi

bash "\$AGG_SCRIPT"
EOF

# Submit aggregation job
if [ ${#ALL_JOB_IDS[@]} -gt 0 ]; then
    AGG_SBATCH_OUTPUT=$(sbatch "$AGG_TEMP_SCRIPT" 2>&1)
    AGG_SBATCH_EXIT_CODE=$?

    if [ $AGG_SBATCH_EXIT_CODE -eq 0 ]; then
        AGG_JOB_ID=$(echo "$AGG_SBATCH_OUTPUT" | awk '{print $4}')
        if [[ -n "$AGG_JOB_ID" && "$AGG_JOB_ID" =~ ^[0-9]+$ ]]; then
            log_info "Submitted aggregation job ${AGG_JOB_ID} (depends on ${#ALL_JOB_IDS[@]} seqkit jobs)"
        else
            log_warn "Failed to parse aggregation job ID from sbatch output"
            log_warn "sbatch output: $AGG_SBATCH_OUTPUT"
            log_warn "You may need to run aggregation manually after seqkit jobs complete"
        fi
    else
        log_warn "Failed to submit aggregation job"
        log_warn "sbatch output: $AGG_SBATCH_OUTPUT"
        log_warn "You may need to run aggregation manually after seqkit jobs complete"
    fi
else
    log_warn "No seqkit jobs were submitted successfully"
    log_warn "Skipping aggregation job submission"
fi

    # Clean up temporary script
    rm -f "$AGG_TEMP_SCRIPT"
else
    log_step "Test mode: skipping aggregation job"
    log_info "Aggregation job skipped in test mode"
fi

log_step "Final summary"
log_info "Total script time: ${TOTAL_ELAPSED} seconds"
log_info "All jobs submitted successfully!"
log_info "Check job status with: squeue -u $USER"
if [ ${#ALL_JOB_IDS[@]} -gt 0 ] && [ -n "$AGG_JOB_ID" ] && [[ "$AGG_JOB_ID" =~ ^[0-9]+$ ]]; then
    log_info ""
    log_info "Pipeline automation:"
    log_info "  - ${#ALL_JOB_IDS[@]} seqkit jobs submitted"
    log_info "  - Aggregation job ${AGG_JOB_ID} will run automatically after all seqkit jobs complete"
    log_info ""
    log_info "Alternative: Use the complete local pipeline (without SLURM):"
    log_info "  pixi run bash tools/gen_syn_samples.sh"
else
    log_info ""
    log_info "After all SLURM jobs complete, run aggregation manually:"
    log_info "  pixi run bash tools/gen_agg_syn_datasets.sh"
fi
