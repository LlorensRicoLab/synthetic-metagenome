#!/bin/bash

# Script to subsample large FASTQ files to 10M reads maximum
# This ensures that no single organism has more reads than the maximum
# bacterial community size we want in our synthetic datasets

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

# Configuration
SOURCE_DIR="${PROJECT_DIR}/data/source_fastq"
MAX_READS=10000000
LOG_FILE="${PROJECT_DIR}/logs/subsample_large_fastq.log"

# Create logs directory if it doesn't exist
mkdir -p "$(dirname "${LOG_FILE}")"

# Function to check if file has more than MAX_READS
check_file_size() {
    local file="$1"
    local reads=$(seqkit stats -T "$file" | tail -n +2 | cut -f4 | sed 's/,//g')
    if [ "$reads" -gt "$MAX_READS" ]; then
        echo "$reads"
    else
        echo "0"
    fi
}

# Function to subsample a file
subsample_file() {
    local file="$1"
    local original_reads="$2"

    log_info "Subsampling $file from $original_reads reads to $MAX_READS reads"

    # Create temporary file
    local temp_file="${file}.tmp"

    # Subsample using seqkit head
    if seqkit head -n "$MAX_READS" "$file" -o "$temp_file"; then
        # Replace original with subsampled version
        mv "$temp_file" "$file"
        log_info "Successfully subsampled $file"
    else
        log_error "Failed to subsample $file"
        rm -f "$temp_file"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting subsampling of large FASTQ files"
    log_info "Source directory: $SOURCE_DIR"
    log_info "Maximum reads per file: $MAX_READS"

    # Load SeqKit module
    log_info "Loading SeqKit module..."
    if ! module load SeqKit 2>/dev/null; then
        log_error "Failed to load SeqKit module"
        exit 1
    fi

    # Check if seqkit is available
    if ! command -v seqkit &> /dev/null; then
        log_error "seqkit not found after loading module"
        exit 1
    fi

    # Find all FASTQ files and check their sizes
    log_info "Scanning for files with more than $MAX_READS reads..."

    local files_to_subsample=()
    local total_files=0
    local processed_files=0

    # Process files in pairs to maintain paired-end structure
    for file1 in "$SOURCE_DIR"/*_1.fastq.gz; do
        if [ ! -f "$file1" ]; then
            continue
        fi

        # Get corresponding _2 file
        file2="${file1/_1.fastq.gz/_2.fastq.gz}"

        if [ ! -f "$file2" ]; then
            log_warn "Paired file $file2 not found for $file1"
            continue
        fi

        total_files=$((total_files + 2))

        # Check read counts for both files
        reads1=$(check_file_size "$file1")
        reads2=$(check_file_size "$file2")

        if [ "$reads1" -gt 0 ] || [ "$reads2" -gt 0 ]; then
            log_info "Found large file pair:"
            log_info "  $file1: $reads1 reads"
            log_info "  $file2: $reads2 reads"

            files_to_subsample+=("$file1:$reads1")
            files_to_subsample+=("$file2:$reads2")
        fi
    done

    if [ ${#files_to_subsample[@]} -eq 0 ]; then
        log_info "No files found with more than $MAX_READS reads"
        exit 0
    fi

    log_info "Found ${#files_to_subsample[@]} files to subsample"

    # Subsample each file
    for file_info in "${files_to_subsample[@]}"; do
        file="${file_info%:*}"
        reads="${file_info#*:}"

        if [ "$reads" -gt 0 ]; then
            if subsample_file "$file" "$reads"; then
                processed_files=$((processed_files + 1))
            else
                log_error "Failed to process $file"
                exit 1
            fi
        fi
    done

    log_info "Subsampling completed successfully!"
    log_info "Processed $processed_files files"

    # Verify results
    log_info "Verifying subsampling results..."
    for file_info in "${files_to_subsample[@]}"; do
        file="${file_info%:*}"
        reads="${file_info#*:}"

        if [ "$reads" -gt 0 ]; then
            new_reads=$(seqkit stats -T "$file" | tail -n +2 | cut -f4 | sed 's/,//g')
            log_info "  $file: $reads -> $new_reads reads"

            if [ "$new_reads" -gt "$MAX_READS" ]; then
                log_warn "$file still has more than $MAX_READS reads ($new_reads)"
            fi
        fi
    done

    log_info "Subsampling verification completed"
}

# Run main function
main "$@"
