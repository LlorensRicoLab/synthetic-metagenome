#!/bin/bash

# Verify Aggregated FASTQ Read Counts Script
# Checks that each aggregated file has the correct number of reads

set -e  # Exit on any error

# Initialize timing variables
SCRIPT_START_TIME=$(date +%s)
SECONDS=0

echo "=== Aggregated FASTQ Read Count Verification ==="
echo "Script started at: $(date)"

# Load environment variables from .env file
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
DATASETS_DIR="${CUSTOM_DATASETS_DIR:-$PROJECT_DIR/data/synthetic/datasets}"



# Define parameter arrays
DIVERSITY_LEVELS=("low" "mid" "high")
DIVERSITY_IDS=({1..5})
SAMPLING_DEPTHS=("10000" "100000" "1000000" "10000000")
STRAND_IDS=("1" "2")

# Function to check a single file
check_file_reads() {
    local file_path="$1"
    local expected_reads="$2"
    local log_file="$3"
    
    if [ ! -f "$file_path" ]; then
        echo "[$(date '+%H:%M:%S')] [ERROR] File not found: " \
            "$(basename "$file_path")" >> "$log_file"
        return 1
    fi
    
    # Count lines in the file
    local line_count=$(zcat "$file_path" | wc -l)
    local actual_reads=$((line_count / 4))
    
    if [ "$actual_reads" -eq "$expected_reads" ]; then
        echo "[$(date '+%H:%M:%S')] [OK] $(basename "$file_path"): " \
            "$actual_reads reads" >> "$log_file"
        return 0
    else
        echo "[$(date '+%H:%M:%S')] [ERROR] $(basename "$file_path"): " \
            "$actual_reads reads (expected: $expected_reads)" >> "$log_file"
        return 1
    fi
}

# Function to check all files for a diversity level + strand combination
check_diversity_strand_verification() {
    local diversity_level="$1"
    local diversity_id="$2"
    local strand_id="$3"
    local log_file="$4"
    
    local aggregated_dir="$DATASETS_DIR/${diversity_level}_diversity/aggregated"
    local job_start_time=$(date +%s)
    
    # Determine strand name
    local strand_name="forward strand"
    if [ "$strand_id" = "2" ]; then
        strand_name="reverse strand"
    fi
    
    local success_count=0
    local failure_count=0
    
    # Check all 4 sampling depths
    # for this diversity_level + diversity_id + strand
    for sampling_depth in "${SAMPLING_DEPTHS[@]}"; do
        local file_path
        file_path=$(printf "%s/%s_%s_%s_%s.fastq.gz" \
            "$aggregated_dir" "$diversity_level" "$diversity_id" \
            "$sampling_depth" "$strand_id")
        
        if check_file_reads "$file_path" "$sampling_depth" "$log_file"; then
            success_count=$(( success_count + 1 ))
        else
            failure_count=$(( failure_count + 1 ))
        fi
    done
    
    local job_elapsed=$(( $(date +%s) - job_start_time ))
    echo -n "[$(date '+%H:%M:%S')] Verification of "
    echo -n "${diversity_level}_${diversity_id} "
    echo -n "${strand_name}: $success_count [OK] $failure_count [ERROR] "
    echo "(${job_elapsed}s)"
    
    return $failure_count
}

# Main verification
echo "[$(date '+%H:%M:%S')] (1/1) Starting verification of aggregated FASTQ files..."

VERIFICATION_START_TIME=$(date +%s)

# Create log directory
LOG_DIR="${CUSTOM_LOGS_DIR:-$PROJECT_DIR/logs}"
mkdir -p "$LOG_DIR"

# Create job tracking arrays
job_pids=()
job_results=()



# Launch 30 parallel verification jobs
for diversity_level in "${DIVERSITY_LEVELS[@]}"; do
    for diversity_id in "${DIVERSITY_IDS[@]}"; do
        for strand_id in "${STRAND_IDS[@]}"; do
            # Create individual log file for this job
            job_log=$(printf "%s/verification_%s_%s_strand%s_%s.log" \
                "$LOG_DIR" "$diversity_level" "$diversity_id" "$strand_id" \
                "$(date +%Y%m%d_%H%M%S)")
            
            # Launch job in background
            check_diversity_strand_verification \
                "$diversity_level" "$diversity_id" \
                "$strand_id" "$job_log" &
            job_pids+=($!)
            job_results+=("${diversity_level}_${diversity_id}_" \
                "strand${strand_id}")
        done
    done
done

# Wait for all verification jobs to complete and collect results
total_success=0
total_failure=0

for i in "${!job_pids[@]}"; do
    pid="${job_pids[$i]}"
    job_name="${job_results[$i]}"
    
    if wait "$pid"; then
        total_success=$(( total_success + 1 ))
    else
        echo "[$(date '+%H:%M:%S')] Verification job $job_name failed (PID: $pid)"
        total_failure=$(( total_failure + 1 ))
    fi
done

VERIFICATION_ELAPSED=$(( $(date +%s) - VERIFICATION_START_TIME ))

# Count total incorrect files from all log files
total_incorrect=0

for diversity_level in "${DIVERSITY_LEVELS[@]}"; do
    for diversity_id in "${DIVERSITY_IDS[@]}"; do
        for strand_id in "${STRAND_IDS[@]}"; do
            # Find the corresponding log file
            log_pattern=$(printf "%s/verification_%s_%s_strand%s_*.log" \
                "$LOG_DIR" "$diversity_level" "$diversity_id" "$strand_id")
            log_file=$(ls -t $log_pattern 2>/dev/null | head -1)
            
            if [ -f "$log_file" ]; then
                # Count incorrect files
                incorrect_count=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null || echo "0")
                # Ensure incorrect_count is numeric to avoid syntax errors
                if [ -n "$incorrect_count" ] && \
                    [ "$incorrect_count" -ge 0 ] 2>/dev/null; then
                    total_incorrect=$(( total_incorrect + incorrect_count ))
                fi
            fi
        done
    done
done

if [ $total_incorrect -eq 0 ]; then
    echo ""
    echo "[OK] All aggregated FASTQ files have the correct number of reads!"
else
    echo ""
    echo "[ERROR] Found $total_incorrect files with incorrect read counts."
fi

echo ""
echo "=== FINAL SUMMARY ==="
echo ""
echo "Timing Summary:"
echo "  Verification: ${VERIFICATION_ELAPSED} seconds"
echo "  Total Script Time: ${SECONDS} seconds"
echo ""
echo "Results Summary:"
echo "  Total files checked: $(( \
    ${#DIVERSITY_LEVELS[@]} * \
    ${#DIVERSITY_IDS[@]} * \
    ${#SAMPLING_DEPTHS[@]} * \
    ${#STRAND_IDS[@]} ))"
echo "  Total incorrect files: $total_incorrect"
echo "  Verification jobs: $total_success successful, $total_failure failed"

if [ $total_failure -eq 0 ]; then
    exit 0
else
    exit 1
fi