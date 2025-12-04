#!/bin/bash

# Aggregated Datasets Generation Script
# Parallel processing with background jobs

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

# Define parameter arrays
DIVERSITY_LEVELS=("low" "mid" "high")
DIVERSITY_IDS=({1..5})
SAMPLING_DEPTHS=("1e+04" "1e+05" "1e+06" "1e+07")
STRAND_IDS=("1" "2")

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

# ============================================================================
# DISCOVERY FUNCTIONS
# ============================================================================

# Function to check a single combination (for parallel processing)
check_single_combination() {
    local diversity_level="$1"
    local diversity_id="$2"
    local sampling_depth="$3"
    local strand_id="$4"

    local fn_id="${diversity_level}_${diversity_id}_${sampling_depth}"
    local agg_dir="$DATASETS_DIR/${diversity_level}_diversity/aggregated"
    local output_file="${agg_dir}/${fn_id}_${strand_id}.fastq.gz"

    # Check if file is missing or corrupted
    if [ ! -f "$output_file" ] || ! check_gzip_file "$output_file"; then
        echo "${fn_id}_${strand_id}"
    fi
}

# Function to check combinations
# for a specific diversity_level + diversity_id + strand
check_diversity_strand_combos() {
    local diversity_level="$1"
    local diversity_id="$2"
    local strand_id="$3"
    local log_file="$4"

    local job_start_time=$(date +%s)

    local miss_combos=()

    # Check all 4 sampling depths
    # for this diversity_level + diversity_id + strand
    for sampling_depth in "${SAMPLING_DEPTHS[@]}"; do
        local result=$(
            check_single_combination \
                "$diversity_level" "$diversity_id" \
                "$sampling_depth" "$strand_id"
        )
        if [ -n "$result" ]; then
            miss_combos+=("$result")
        fi
    done

    # Output missing combinations to log file
    for combo in "${miss_combos[@]}"; do
        echo "$combo" >> "$log_file"
    done

    local job_elapsed=$(( $(date +%s) - job_start_time ))

    # Determine strand name
    local strand_name=""
    if [ "$strand_id" = "1" ]; then
        strand_name="forward strand"
    elif [ "$strand_id" = "2" ]; then
        strand_name="reverse strand"
    else
        log_error "Invalid strand ID: $strand_id"
        return 1
    fi

    log_info "Discovery ${diversity_level}_${diversity_id} ${strand_name}: ${#miss_combos[@]} missing (${job_elapsed}s)"
    return 0  # Always return success, missing count is handled separately
}

# ============================================================================
# AGGREGATION FUNCTIONS
# ============================================================================

# Function to (re)generate a single aggregated dataset
gen_agg_dataset() {
    local diversity_level="$1"
    local diversity_id="$2"
    local sampling_depth="$3"
    local strand_id="$4"

    local dataset_dir="$DATASETS_DIR/${diversity_level}_diversity"
    local fn_id="${diversity_level}_${diversity_id}_${sampling_depth}"
    local ind_dir="$dataset_dir/individual"
    local agg_dir="$dataset_dir/aggregated"
    local output_file="${agg_dir}/${fn_id}_${strand_id}.fastq.gz"

    # Create aggregated directory if it doesn't exist
    mkdir -p "$agg_dir"

    # Find all individual files for this combination
    local fn_id="${diversity_level}_${diversity_id}_${sampling_depth}"
    local pattern="*_${fn_id}_${strand_id}.fastq.gz"
    local individual_files=()

    while IFS= read -r -d '' file; do
        individual_files+=("$file")
    done < <(find "$ind_dir" -name "$pattern" -print0)

    if [ ${#individual_files[@]} -eq 0 ]; then
        log_error "No individual files found for pattern: $pattern"
        return 1
    fi

    # Check which files are valid
    local valid_files=()
    for file in "${individual_files[@]}"; do
        if check_gzip_file "$file"; then
            valid_files+=("$file")
        else
            log_warn "Corrupted file: $file"
        fi
    done

    if [ ${#valid_files[@]} -eq 0 ]; then
        log_error "No valid individual files found"
        return 1
    fi

    # Sort valid_files array to ensure deterministic aggregation order
    IFS=$'\n' valid_files=($(sort <<<"${valid_files[*]}"))
    unset IFS

    # Combine individual files into aggregated dataset
    cat "${valid_files[@]}" > "$output_file"

    # Verify the generated file
    if check_gzip_file "$output_file"; then
        log_info "Aggregated ${#valid_files[@]} files into ${output_file}"
        return 0
    else
        log_error "Failed to regenerate: $output_file"
        return 1
    fi
}

# Function to process all sampling depths
# for a single diversity_level + diversity_id + strand
gen_agg_datasets_per_combo() {
    local diversity_level="$1"
    local diversity_id="$2"
    local strand_id="$3"
    local log_file="$4"

    local job_start_time=$(date +%s)

    local success_count=0
    local failure_count=0
    local num_files=()

    # Process all 4 sampling depths
    # for this diversity_level + diversity_id + strand
    for sampling_depth in "${SAMPLING_DEPTHS[@]}"; do
        # Capture the output to extract file count
        local output=$(
            gen_agg_dataset \
                "$diversity_level" "$diversity_id" \
                "$sampling_depth" "$strand_id" 2>&1
        )
        local exit_code=$?

        # Extract file count from success message
        local success_line=$(echo "$output" | grep "Successfully aggregated")
        if [ -n "$success_line" ]; then
            num_files_i=$(echo "$success_line" | \
                sed 's/.*Successfully aggregated \([0-9]*\) files.*/\1/')
            if [ "$num_files_i" -gt 0 ] 2>/dev/null; then
                num_files+=("$num_files_i")
            else
                num_files+=("0")
            fi
        else
            num_files+=("0")
        fi

        # Output to log file
        echo "$output" >> "$log_file"

        if [ $exit_code -eq 0 ]; then
            success_count=$(( success_count + 1 ))
        else
            failure_count=$(( failure_count + 1 ))
        fi
    done

    # Determine strand name
    local strand_name=""
    if [ "$strand_id" = "1" ]; then
        strand_name="forward strand"
    elif [ "$strand_id" = "2" ]; then
        strand_name="reverse strand"
    else
        log_error "Invalid strand ID: $strand_id"
        return 1
    fi

    # Format file counts as comma-separated list in parentheses
    local num_files_str="(${num_files[*]// /, })"

    local job_elapsed=$(( $(date +%s) - job_start_time ))
    log_info "Aggregation ${diversity_level}_${diversity_id} ${strand_name}: files ${num_files_str}, success ${success_count}, failure ${failure_count} (${job_elapsed}s)"

    return $failure_count
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# ---------------------------------------------------------
# SCRIPT STARTUP AND PROJECT STRUCTURE DETECTION
# ---------------------------------------------------------

# Initialize timing variables
SCRIPT_START_TIME=$(date +%s)
SECONDS=0

# Auto-detect workspace root directory
ROOT_SEARCH_DEPTH="${SMG_ROOT_MAX_DEPTH:-10}"
PROJECT_DIR=$(find_workspace_root "${SCRIPT_DIR}")
if [[ -z "$PROJECT_DIR" ]]; then
    echo "[ERROR] Could not detect workspace root directory after searching $ROOT_SEARCH_DEPTH levels up from ${SCRIPT_DIR}" >&2
    echo "[ERROR] Looking for: .here, .git, pixi.lock, or .env" >&2
    echo "[ERROR] Run this script from within the project tree." >&2
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

# Derive project paths from workspace root based on known structure
PROJECT_DIR="$PROJECT_DIR"
DATASETS_DIR="$PROJECT_DIR/data/datasets"
LOGS_DIR="$PROJECT_DIR/logs"

# Validate that the derived directories exist and are accessible
if [[ ! -d "$DATASETS_DIR" ]]; then
    log_error "DATASETS_DIR does not exist: $DATASETS_DIR"
    log_error "Please ensure the project structure is correct."
    exit 1
fi

if [[ ! -r "$DATASETS_DIR" ]]; then
    log_error "DATASETS_DIR is not readable: $DATASETS_DIR"
    exit 1
fi

log_info "Project structure validated"
log_info "  PROJECT_DIR: $PROJECT_DIR"
log_info "  DATASETS_DIR: $DATASETS_DIR"
log_info "  LOGS_DIR: $LOGS_DIR"

# Create log directory if it doesn't exist
mkdir -p "$LOGS_DIR"
LOG_FILE="$LOGS_DIR/gen_agg_syn_datasets_$(date +%Y%m%d_%H%M%S).log"

log_info "Environment setup complete. Starting main execution..."

# ---------------------------------------------------------
# DISCOVERY PHASE
# ---------------------------------------------------------

# ---------------------------------------------------------
# DISCOVERY PHASE
# ---------------------------------------------------------

# Background discovery phase
log_step "(1/2) Scanning for missing aggregated datasets"

PHASE1_START_TIME=$(date +%s)
PHASE1_SECONDS=0

# Create job tracking arrays for discovery
discovery_pids=()
discovery_logs=()

# Launch 30 background discovery jobs
for diversity_level in "${DIVERSITY_LEVELS[@]}"; do
    for diversity_id in "${DIVERSITY_IDS[@]}"; do
        for strand_id in "${STRAND_IDS[@]}"; do
            # Create individual log file for this discovery job
            discovery_log=$(printf "%s/discovery_%s_%s_strand%s_%s.log" \
                "$LOGS_DIR" "$diversity_level" "$diversity_id" "$strand_id" \
                "$(date +%Y%m%d_%H%M%S)")

            # Create empty log file (directory already exists)
            touch "$discovery_log" 2>/dev/null || {
                log_warn "Could not create log file: $discovery_log"
            }

            # Launch discovery job in background
            check_diversity_strand_combos \
                "$diversity_level" "$diversity_id" \
                "$strand_id" "$discovery_log" &
            discovery_pids+=($!)
            discovery_logs+=("$discovery_log")
        done
    done
done

# Wait for all discovery jobs to complete
total_missing=0

for i in "${!discovery_pids[@]}"; do
    pid="${discovery_pids[$i]}"
    log_file="${discovery_logs[$i]}"

    if wait "$pid"; then
        # Count missing combinations from log file
        missing_count=$(wc -l < "$log_file" 2>/dev/null || echo "0")
        total_missing=$((total_missing + missing_count))
    else
        log_error "Discovery job failed (PID: $pid)"
    fi
done

# Collect all missing combinations
miss_combos=()
for log_file in "${discovery_logs[@]}"; do
    if [ -f "$log_file" ] && [ -r "$log_file" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                miss_combos+=("$line")
            fi
        done < "$log_file" 2>/dev/null || true
    else
        log_warn "Could not read log file: $log_file"
    fi
done

PHASE1_ELAPSED=$(( $(date +%s) - PHASE1_START_TIME ))
log_info "Found ${#miss_combos[@]} missing/corrupted aggregated datasets in ${PHASE1_ELAPSED} seconds"

if [ ${#miss_combos[@]} -eq 0 ]; then
    log_info "No missing aggregated datasets found."
    log_info "Total script time: ${SECONDS} seconds"
    exit 0
fi

# ---------------------------------------------------------
# AGGREGATION PHASE
# ---------------------------------------------------------

# Group missing combinations by diversity_id + diversity_level + strand
log_step "(2/2) Aggregating missing datasets"

PHASE2_START_TIME=$(date +%s)
PHASE2_SECONDS=0

# Create job tracking arrays for aggregation
job_pids=()
job_results=()

# Launch 30 parallel aggregation jobs
for diversity_level in "${DIVERSITY_LEVELS[@]}"; do
    for diversity_id in "${DIVERSITY_IDS[@]}"; do
        for strand_id in "${STRAND_IDS[@]}"; do
            # Create individual log file for this job
            job_log=$(printf "%s/agg_regen_%s_%s_strand%s_%s.log" \
                "$LOGS_DIR" "$diversity_level" "$diversity_id" "$strand_id" \
                "$(date +%Y%m%d_%H%M%S)")

            # Launch job in background
            gen_agg_datasets_per_combo \
                "$diversity_level" "$diversity_id" \
                "$strand_id" "$job_log" &
            job_pids+=($!)
            job_id="${diversity_level}_${diversity_id}_${strand_id}"
            job_results+=("$job_id")
        done
    done
done

# Wait for all aggregation jobs to complete and collect results
total_succ=0
total_fail=0
total_files_agg=0
total_files_fail=0

for i in "${!job_pids[@]}"; do
    pid="${job_pids[$i]}"
    job_name="${job_results[$i]}"

    if wait "$pid"; then
        total_succ=$(( total_succ + 1 ))
        # Each successful job aggregates 4 files (one per sampling depth)
        total_files_agg=$(( total_files_agg + 4 ))
    else
        log_error "Aggregation job $job_name failed (PID: $pid)"
        total_fail=$(( total_fail + 1 ))
        # Each failed job means 4 files failed to aggregate
        total_files_fail=$(( total_files_fail + 4 ))
    fi
done

PHASE2_ELAPSED=$(( $(date +%s) - PHASE2_START_TIME ))
TOTAL_ELAPSED=$(( $(date +%s) - SCRIPT_START_TIME ))

# ---------------------------------------------------------
# CLEANUP AND FINAL SUMMARY
# ---------------------------------------------------------

# Clean up temporary log files
log_info "Cleaning up temporary log files..."

# Remove discovery phase logs
for log_file in "${discovery_logs[@]}"; do
    if [ -f "$log_file" ]; then
        rm -f "$log_file" 2>/dev/null || {
            log_warn "Could not remove discovery log: $log_file"
        }
    fi
done

# Remove aggregation phase logs
for log_file in "${job_logs[@]}"; do
    if [ -f "$log_file" ]; then
        rm -f "$log_file" 2>/dev/null || {
            log_warn "Could not remove aggregation log: $log_file"
        }
    fi
done

log_info "Cleanup complete. Keeping main execution log: $LOG_FILE"

log_step "Final summary"
log_info "Discovery: ${PHASE1_ELAPSED} seconds"
log_info "Aggregation: ${PHASE2_ELAPSED} seconds"
log_info "Total script time: ${TOTAL_ELAPSED} seconds"
log_info "Missing/corrupted files found: ${#miss_combos[@]}"
log_info "Files successfully aggregated: $total_files_agg"
log_info "Files failed to aggregate: $total_files_fail"
log_info "Aggregation jobs: $total_succ successful, $total_fail failed"

if [ $total_fail -gt 0 ]; then
    log_warn "Some aggregation jobs failed. Check individual log files for details."
    log_warn "Log files: $LOGS_DIR/*_$(date +%Y%m%d_%H%M%S).log"
    exit 1
fi
