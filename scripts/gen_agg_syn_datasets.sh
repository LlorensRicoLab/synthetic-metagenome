#!/bin/bash

# Aggregated Datasets Generation Script
# Parallel processing with background jobs

set -e  # Exit on any error

# Initialize timing variables
SCRIPT_START_TIME=$(date +%s)
SECONDS=0

echo "=== Aggregated Datasets Generation Script ==="
echo "Script started at: $(date)"

# Load environment variables from .env file
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Warning: .env file not found. Using default paths."
fi

# Configuration with environment variable support
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
DATASETS_DIR="${CUSTOM_DATASETS_DIR:-$PROJECT_DIR/data/synthetic/datasets}"
SOURCE_FASTQ_DIR="$PROJECT_DIR/data/synthetic/generation/source_fastq"
LOG_DIR="${CUSTOM_LOGS_DIR:-$PROJECT_DIR/logs}"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/gen_agg_syn_datasets_$(date +%Y%m%d_%H%M%S).log"

# Define parameter arrays
DIVERSITY_LEVELS=("low" "mid" "high")
DIVERSITY_IDS=({1..5})
SAMPLING_DEPTHS=("10000" "100000" "1000000" "10000000")
STRAND_IDS=("1" "2")

# Function to check if a gzip file is valid
check_gzip_file() {
    local file="$1"
    if gzip -t "$file" 2>/dev/null; then
        return 0  # File is valid
    else
        return 1  # File is corrupted
    fi
}

# Function to check a single combination (for parallel processing)
check_single_combination() {
    local diversity_level="$1"
    local diversity_id="$2"
    local sampling_depth="$3"
    local strand_id="$4"
    
    local aggregated_dir="$DATASETS_DIR/${diversity_level}_diversity/aggregated"
    local output_file="${aggregated_dir}/${diversity_level}_${diversity_id}_${sampling_depth}_${strand_id}.fastq.gz"
    
    # Check if file is missing or corrupted
    if [ ! -f "$output_file" ] || ! check_gzip_file "$output_file"; then
        echo "${diversity_level}_${diversity_id}_${sampling_depth}_${strand_id}"
    fi
}

# Function to check combinations
# for a specific diversity_level + diversity_id + strand
check_diversity_strand_combinations() {
    local diversity_level="$1"
    local diversity_id="$2"
    local strand_id="$3"
    local log_file="$4"
    
    local job_start_time=$(date +%s)
    
    local missing_combinations=()
    
    # Check all 4 sampling depths
    # for this diversity_level + diversity_id + strand
    for sampling_depth in "${SAMPLING_DEPTHS[@]}"; do
        local result=$(
            check_single_combination \
                "$diversity_level" "$diversity_id" \
                "$sampling_depth" "$strand_id"
        )
        if [ -n "$result" ]; then
            missing_combinations+=("$result")
        fi
    done
    
    # Output missing combinations to log file
    for combination in "${missing_combinations[@]}"; do
        echo "$combination" >> "$log_file"
    done
    
    local job_elapsed=$(( $(date +%s) - job_start_time ))
    
    # Determine strand name
    local strand_name="forward strand"
    if [ "$strand_id" = "2" ]; then
        strand_name="reverse strand"
    fi
    
    echo -n "[$(date '+%H:%M:%S')]   Looking for aggregated datasets for "
    echo -n "${diversity_level}_${diversity_id} ${strand_name}: "
    echo "${#missing_combinations[@]} missing (${job_elapsed}s)"
    return 0  # Always return success, missing count is handled separately
}

# Function to regenerate a single aggregated dataset
regenerate_aggregated_dataset() {
    local diversity_level="$1"
    local diversity_id="$2"
    local sampling_depth="$3"
    local strand_id="$4"
    
    local individual_dir="$DATASETS_DIR/${diversity_level}_diversity/individual"
    local aggregated_dir="$DATASETS_DIR/${diversity_level}_diversity/aggregated"
    local output_file="${aggregated_dir}/${diversity_level}_${diversity_id}_${sampling_depth}_${strand_id}.fastq.gz"
    
    # Create aggregated directory if it doesn't exist
    mkdir -p "$aggregated_dir"
    
    # Find all individual files for this combination
    local pattern="*_${diversity_level}_${diversity_id}_${sampling_depth}_${strand_id}.fastq.gz"
    local individual_files=()
    
    while IFS= read -r -d '' file; do
        individual_files+=("$file")
    done < <(find "$individual_dir" -name "$pattern" -print0)
    
    if [ ${#individual_files[@]} -eq 0 ]; then
        echo "  ✗ No individual files found for pattern: $pattern"
        return 1
    fi
    
    # Check which files are valid
    local valid_files=()
    for file in "${individual_files[@]}"; do
        if check_gzip_file "$file"; then
            valid_files+=("$file")
        else
            echo "  Warning: Corrupted file: $file"
        fi
    done
    
    if [ ${#valid_files[@]} -eq 0 ]; then
        echo "  ✗ No valid individual files found"
        return 1
    fi
    
    # Combine individual files into aggregated dataset
    cat "${valid_files[@]}" > "$output_file"
    
    # Verify the generated file
    if check_gzip_file "$output_file"; then
        echo "  ✓ Successfully aggregated ${#valid_files[@]} files in: $output_file"
        return 0
    else
        echo "  ✗ Failed to regenerate: $output_file"
        return 1
    fi
}

# Function to process all sampling depths
# for a single diversity_level + diversity_id + strand
process_diversity_strand_simulation() {
    local diversity_level="$1"
    local diversity_id="$2"
    local strand_id="$3"
    local log_file="$4"
    
    local job_start_time=$(date +%s)
    
    local success_count=0
    local failure_count=0
    local total_files=0
    local file_counts=()
    
    # Process all 4 sampling depths
    # for this diversity_level + diversity_id + strand
    for sampling_depth in "${SAMPLING_DEPTHS[@]}"; do
        # Capture the output to extract file count
        local output=$(
            regenerate_aggregated_dataset \
                "$diversity_level" "$diversity_id" \
                "$sampling_depth" "$strand_id" 2>&1
        )
        local exit_code=$?
        
        # Extract file count from success message
        if echo "$output" | grep -q "Successfully aggregated"; then
            file_count=$(echo "$output" | grep "Successfully aggregated" | \
                sed 's/.*Successfully aggregated \([0-9]*\) files.*/\1/')
            if [ "$file_count" -gt 0 ] 2>/dev/null; then
                total_files=$((total_files + file_count))
                file_counts+=("$file_count")
            else
                file_counts+=("0")
            fi
        else
            file_counts+=("0")
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
    local strand_name="forward strand"
    if [ "$strand_id" = "2" ]; then
        strand_name="reverse strand"
    fi
    
    # Format file counts as comma-separated list in parentheses
    local file_count_str="(${file_counts[*]// /, })"
    
    local job_elapsed=$(( $(date +%s) - job_start_time ))
    echo -n "[$(date '+%H:%M:%S')]   Aggregation of $file_count_str files for "
    echo -n "${diversity_level}_${diversity_id} ${strand_name}: "
    echo "$success_count✓ $failure_count✗ (${job_elapsed}s)"
    return $failure_count
}

# Background discovery phase
echo "[$(date '+%H:%M:%S')] (1/2) Scanning for missing aggregated datasets..."


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
                "$LOG_DIR" "$diversity_level" "$diversity_id" "$strand_id" \
                "$(date +%Y%m%d_%H%M%S)")
            
            # Ensure log directory exists and create empty log file
            mkdir -p "$LOG_DIR"
            touch "$discovery_log" 2>/dev/null || {
                echo -n "[$(date '+%H:%M:%S')] Warning: Could not create log file: "
                echo "$discovery_log"
            }
            
            # Launch discovery job in background
            check_diversity_strand_combinations \
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
        echo "[$(date '+%H:%M:%S')] ✗ Discovery job failed (PID: $pid)"
    fi
done

# Collect all missing combinations
missing_combinations=()
for log_file in "${discovery_logs[@]}"; do
    if [ -f "$log_file" ] && [ -r "$log_file" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                missing_combinations+=("$line")
            fi
        done < "$log_file" 2>/dev/null || true
    else
        echo -n "[$(date '+%H:%M:%S')] Warning: Could not read log file: "
        echo "$log_file"
    fi
done

PHASE1_ELAPSED=$(( $(date +%s) - PHASE1_START_TIME ))
echo -n "Found ${#missing_combinations[@]} "
echo "missing/corrupted aggregated datasets in ${PHASE1_ELAPSED} seconds"

if [ ${#missing_combinations[@]} -eq 0 ]; then
    echo "No missing aggregated datasets found."
    echo "Total script time: ${SECONDS} seconds"
    exit 0
fi

# Group missing combinations by diversity_id + diversity_level + strand
echo "[$(date '+%H:%M:%S')] (2/2) Aggregating missing datasets..."

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
            job_log=$(printf "%s/aggregated_regeneration_%s_%s_strand%s_%s.log" \
                "$LOG_DIR" "$diversity_level" "$diversity_id" "$strand_id" \
                "$(date +%Y%m%d_%H%M%S)")
            
            # Launch job in background
            process_diversity_strand_simulation \
                "$diversity_level" "$diversity_id" \
                "$strand_id" "$job_log" &
            job_pids+=($!)
            job_results+=("${diversity_level}_${diversity_id}_strand${strand_id}")
        done
    done
done

# Wait for all aggregation jobs to complete and collect results
total_success=0
total_failure=0
total_files_aggregated=0
total_files_failed=0

for i in "${!job_pids[@]}"; do
    pid="${job_pids[$i]}"
    job_name="${job_results[$i]}"
    
    if wait "$pid"; then
        total_success=$(( total_success + 1 ))
        # Each successful job aggregates 4 files (one per sampling depth)
        total_files_aggregated=$(( total_files_aggregated + 4 ))
    else
        echo "✗ Aggregation job $job_name failed (PID: $pid)"
        total_failure=$(( total_failure + 1 ))
        # Each failed job means 4 files failed to aggregate
        total_files_failed=$(( total_files_failed + 4 ))
    fi
done

PHASE2_ELAPSED=$(( $(date +%s) - PHASE2_START_TIME ))
TOTAL_ELAPSED=$(( $(date +%s) - SCRIPT_START_TIME ))

echo ""
echo "=== FINAL SUMMARY ==="
echo ""
echo "Timing Summary:"
echo "  Discovery: ${PHASE1_ELAPSED} seconds"
echo "  Aggregation: ${PHASE2_ELAPSED} seconds"
echo "  Total Script Time: ${TOTAL_ELAPSED} seconds"
echo ""
echo "Results Summary:"
echo "  Missing/corrupted files found: ${#missing_combinations[@]}"
echo "  Files successfully aggregated: $total_files_aggregated"
echo "  Files failed to aggregate: $total_files_failed"
echo "  Aggregation jobs: $total_success successful, $total_failure failed"

if [ $total_failure -gt 0 ]; then
    echo "Some aggregation jobs failed. Check individual log files for details."
    echo "  Log files: $LOG_DIR/*_$(date +%Y%m%d_%H%M%S).log"
    exit 1
fi 