#!/bin/bash

# Script to subsample large FASTQ files to 10M reads maximum
# This ensures that no single organism has more reads than the maximum
# bacterial community size we want in our synthetic datasets

set -e  # Exit on any error

# Configuration
SOURCE_DIR="data/synthetic/generation/source_fastq"
MAX_READS=10000000
LOG_FILE="logs/subsample_large_fastq.log"

# Create logs directory if it doesn't exist
mkdir -p logs

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

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
    
    log "Subsampling $file from $original_reads reads to $MAX_READS reads"
    
    # Create temporary file
    local temp_file="${file}.tmp"
    
    # Subsample using seqkit head
    if seqkit head -n "$MAX_READS" "$file" -o "$temp_file"; then
        # Replace original with subsampled version
        mv "$temp_file" "$file"
        log "Successfully subsampled $file"
    else
        log "ERROR: Failed to subsample $file"
        rm -f "$temp_file"
        return 1
    fi
}

# Main execution
main() {
    log "Starting subsampling of large FASTQ files"
    log "Source directory: $SOURCE_DIR"
    log "Maximum reads per file: $MAX_READS"
    
    # Load SeqKit module
    log "Loading SeqKit module..."
    if ! module load SeqKit 2>/dev/null; then
        log "ERROR: Failed to load SeqKit module"
        exit 1
    fi
    
    # Check if seqkit is available
    if ! command -v seqkit &> /dev/null; then
        log "ERROR: seqkit not found after loading module"
        exit 1
    fi
    
    # Find all FASTQ files and check their sizes
    log "Scanning for files with more than $MAX_READS reads..."
    
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
            log "WARNING: Paired file $file2 not found for $file1"
            continue
        fi
        
        total_files=$((total_files + 2))
        
        # Check read counts for both files
        reads1=$(check_file_size "$file1")
        reads2=$(check_file_size "$file2")
        
        if [ "$reads1" -gt 0 ] || [ "$reads2" -gt 0 ]; then
            log "Found large file pair:"
            log "  $file1: $reads1 reads"
            log "  $file2: $reads2 reads"
            
            files_to_subsample+=("$file1:$reads1")
            files_to_subsample+=("$file2:$reads2")
        fi
    done
    
    if [ ${#files_to_subsample[@]} -eq 0 ]; then
        log "No files found with more than $MAX_READS reads"
        exit 0
    fi
    
    log "Found ${#files_to_subsample[@]} files to subsample"
    
    # Subsample each file
    for file_info in "${files_to_subsample[@]}"; do
        file="${file_info%:*}"
        reads="${file_info#*:}"
        
        if [ "$reads" -gt 0 ]; then
            if subsample_file "$file" "$reads"; then
                processed_files=$((processed_files + 1))
            else
                log "ERROR: Failed to process $file"
                exit 1
            fi
        fi
    done
    
    log "Subsampling completed successfully!"
    log "Processed $processed_files files"
    
    # Verify results
    log "Verifying subsampling results..."
    for file_info in "${files_to_subsample[@]}"; do
        file="${file_info%:*}"
        reads="${file_info#*:}"
        
        if [ "$reads" -gt 0 ]; then
            new_reads=$(seqkit stats -T "$file" | tail -n +2 | cut -f4 | sed 's/,//g')
            log "  $file: $reads -> $new_reads reads"
            
            if [ "$new_reads" -gt "$MAX_READS" ]; then
                log "WARNING: $file still has more than $MAX_READS reads ($new_reads)"
            fi
        fi
    done
    
    log "Subsampling verification completed"
}

# Run main function
main "$@" 