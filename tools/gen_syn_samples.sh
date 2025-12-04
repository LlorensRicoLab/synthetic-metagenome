#!/bin/bash

# Synthetic Samples Generation Script
# Local processing without SLURM dependency
# Generates individual FASTQ files via seqkit subsampling and aggregates them

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

# Define parameter arrays
READ_COUNTS=("1e+04" "1e+05" "1e+06" "1e+07")

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Function to check if a gzip file is valid
check_gzip_file() {
    local file="$1"
    if gzip -t "$file" 2>/dev/null; then
        return 0  # File is valid
    else
        return 1  # File is corrupted
    fi
}

# Function to process a single subsampling specification
process_single_spec() {
    local spec_line="$1"
    local source_dir="$2"
    local output_dir="$3"
    local log_file="$4"

    # Parse the specification line
    # Format: input_file seed num_reads output_path
    local input_file
    local seed
    local num_reads
    local output_path

    input_file=$(echo "$spec_line" | awk '{ print $1 }')
    seed=$(echo "$spec_line" | awk '{ print $2 }')
    num_reads=$(echo "$spec_line" | awk '{ print $3 }')
    output_path=$(echo "$spec_line" | awk '{ print $4 }')

    local input_full_path="${source_dir}/${input_file}"
    local output_full_path="${output_dir}/${output_path}"

    # Check if input file exists
    if [ ! -f "$input_full_path" ]; then
        echo "[$(date '+%H:%M:%S')] [ERROR] Input file not found: $input_file" >> "$log_file"
        return 1
    fi

    # Check if output file already exists and is valid
    if [ -f "$output_full_path" ] && check_gzip_file "$output_full_path"; then
        echo "[$(date '+%H:%M:%S')] [SKIP] Output file already exists: $(basename "$output_path")" >> "$log_file"
        return 0
    fi

    # Create output directory if it doesn't exist
    local output_file_dir
    output_file_dir=$(dirname "$output_full_path")
    mkdir -p "$output_file_dir"

    # Run seqkit subsampling
    # Using pixi run to access seqkit from the pixi environment
    if pixi run seqkit shuffle -s "$seed" "$input_full_path" -o - 2>> "$log_file" | \
       pixi run seqkit head -n "$num_reads" -o "$output_full_path" 2>> "$log_file"; then
        # Verify the output file
        if check_gzip_file "$output_full_path"; then
            echo "[$(date '+%H:%M:%S')] [OK] Processed: $(basename "$output_path") (reads: $num_reads, seed: $seed)" >> "$log_file"
            return 0
        else
            echo "[$(date '+%H:%M:%S')] [ERROR] Output file is corrupted: $(basename "$output_path")" >> "$log_file"
            rm -f "$output_full_path"
            return 1
        fi
    else
        echo "[$(date '+%H:%M:%S')] [ERROR] Failed to process: $(basename "$output_path")" >> "$log_file"
        rm -f "$output_full_path"
        return 1
    fi
}

# Function to process all specifications for a single sampling depth
process_sampling_depth() {
    local read_count="$1"
    local spec_file="$2"
    local source_dir="$3"
    local output_dir="$4"
    local log_file="$5"
    local max_parallel="${6:-8}"

    local job_start_time=$(date +%s)
    local total_specs=0

    # Read all specifications
    local specs=()
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -n "$line" ]; then
            specs+=("$line")
            total_specs=$((total_specs + 1))
        fi
    done < "$spec_file"

    if [ $total_specs -eq 0 ]; then
        log_warn "No specifications found in $spec_file"
        return 0
    fi

    log_info "Processing ${read_count} reads: ${total_specs} specifications"

    # Launch jobs in parallel with limit
    local job_pids=()
    local job_count=0

    for spec_line in "${specs[@]}"; do
        # Wait for a slot if we've reached max parallel jobs
        while [ ${#job_pids[@]} -ge $max_parallel ]; do
            # Check which jobs have completed
            local new_pids=()
            for pid in "${job_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    # Job is still running
                    new_pids+=("$pid")
                else
                    # Job has completed, wait to get exit status
                    wait "$pid" 2>/dev/null || true
                fi
            done
            job_pids=("${new_pids[@]}")
            sleep 0.1
        done

        # Launch new job
        process_single_spec "$spec_line" "$source_dir" "$output_dir" "$log_file" &
        job_pids+=($!)
        job_count=$((job_count + 1))
    done

    # Wait for all remaining jobs to complete
    for pid in "${job_pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Count results from log file
    local success_count=$(grep -c "\[OK\]" "$log_file" 2>/dev/null || echo "0")
    local skip_count=$(grep -c "\[SKIP\]" "$log_file" 2>/dev/null || echo "0")
    local failure_count=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null || echo "0")

    local job_elapsed=$(( $(date +%s) - job_start_time ))
    log_info "Completed ${read_count} reads: ${success_count} success, ${skip_count} skipped, ${failure_count} failed (${job_elapsed}s)"

    return $failure_count
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

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
SYN_SPECS_DIR="$PROJECT_DIR/data/syn_specs"
SOURCE_DIR="$PROJECT_DIR/data/source_fastq"
OUTPUT_DIR="$PROJECT_DIR/data/datasets"
LOGS_DIR="$PROJECT_DIR/logs"
MAX_PARALLEL="${MAX_PARALLEL_JOBS:-8}"

# Create necessary directories
mkdir -p "$LOGS_DIR"
mkdir -p "$OUTPUT_DIR/low_diversity/individual"
mkdir -p "$OUTPUT_DIR/mid_diversity/individual"
mkdir -p "$OUTPUT_DIR/high_diversity/individual"

log_info "Project structure validated"
log_info "  PROJECT_DIR: $PROJECT_DIR"
log_info "  SYN_SPECS_DIR: $SYN_SPECS_DIR"
log_info "  SOURCE_DIR: $SOURCE_DIR"
log_info "  OUTPUT_DIR: $OUTPUT_DIR"
log_info "  LOGS_DIR: $LOGS_DIR"
log_info "  MAX_PARALLEL: $MAX_PARALLEL"

# Validate that source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    log_error "Source FASTQ directory not found: $SOURCE_DIR"
    exit 1
fi

# Validate that syn_specs directory exists
if [[ ! -d "$SYN_SPECS_DIR" ]]; then
    log_error "Synthetic specifications directory not found: $SYN_SPECS_DIR"
    log_error "Please run gen_syn_specs.R first to generate the specification files"
    exit 1
fi

# Check if pixi is available
if ! command -v pixi &> /dev/null; then
    log_error "pixi command not found. Please install pixi or activate the pixi environment"
    exit 1
fi

# Process each sampling depth
TOTAL_START_TIME=$(date +%s)
total_success=0
total_failure=0
total_skipped=0

for read_count in "${READ_COUNTS[@]}"; do
    spec_file="${SYN_SPECS_DIR}/seqkit_subsampling_specs_${read_count}.txt"

    if [ ! -f "$spec_file" ]; then
        log_warn "Specification file not found: $spec_file"
        log_warn "Skipping ${read_count} reads"
        continue
    fi

    log_file="${LOGS_DIR}/gen_indiv_${read_count}_$(date +%Y%m%d_%H%M%S).log"
    touch "$log_file"

    if process_sampling_depth "$read_count" "$spec_file" "$SOURCE_DIR" "$OUTPUT_DIR" "$log_file" "$MAX_PARALLEL"; then
        # Count results from log file
        local success=$(grep -c "\[OK\]" "$log_file" 2>/dev/null || echo "0")
        local skipped=$(grep -c "\[SKIP\]" "$log_file" 2>/dev/null || echo "0")
        local failed=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null || echo "0")
        total_success=$((total_success + success))
        total_skipped=$((total_skipped + skipped))
        total_failure=$((total_failure + failed))
    else
        log_error "Failed to process ${read_count} reads"
    fi
done

TOTAL_ELAPSED=$(( $(date +%s) - TOTAL_START_TIME ))

log_step "Final summary"
log_info "Total processing time: ${TOTAL_ELAPSED} seconds"
log_info "Total script time: ${SECONDS} seconds"
log_info "Successfully processed: $total_success files"
log_info "Skipped (already exist): $total_skipped files"
log_info "Failed: $total_failure files"

if [ $total_failure -gt 0 ]; then
    log_warn "Some files failed to process. Check log files in $LOGS_DIR for details"
    log_warn "Skipping aggregation due to failures in individual file generation"
    exit 1
fi

# ---------------------------------------------------------
# AGGREGATION PHASE
# ---------------------------------------------------------

log_step "Aggregating individual files into synthetic samples"
log_info "Calling gen_agg_syn_datasets.sh to aggregate individual FASTQ files..."

AGG_SCRIPT="${SCRIPT_DIR}/gen_agg_syn_datasets.sh"
if [ ! -f "$AGG_SCRIPT" ]; then
    log_error "Aggregation script not found: $AGG_SCRIPT"
    exit 1
fi

if bash "$AGG_SCRIPT"; then
    log_info "Aggregation completed successfully"
else
    log_error "Aggregation failed"
    exit 1
fi

log_step "Final summary"
log_info "Total script time: ${SECONDS} seconds"
log_info "Successfully processed: $total_success individual files"
log_info "Skipped (already exist): $total_skipped files"
log_info "Synthetic samples generation complete!"
exit 0
