#!/usr/bin/env Rscript

#' @title FASTQ Dataset Validation Tests
#' @description Validates FASTQ file integrity, format, and content
#' @author Francisco Merino-Casallo
#' @date 2025-08-06

# Load required libraries
suppressPackageStartupMessages({
  library(tidyverse)
  library(testthat)
  library(here)
  library(parallel)
  library(cli)
  library(jsonlite)
})

# Set up test context
context("FASTQ Synthetic Dataset Validation Tests")

# Test configuration
DATASET_DIR <- here("data/synthetic/datasets")
EXPECTED_DIVERSITY_LEVELS <- c("low", "mid", "high")
EXPECTED_READ_COUNTS <- c(10000, 100000, 1000000, 10000000)
CACHE_DIR <- here("data", "synthetic", "datasets", "cache")
CACHE_FILE <- file.path(CACHE_DIR, "syn_dataset_validation_cache.json")

# =============================================================================
# CACHING FUNCTIONS
# =============================================================================

#' @title Ensure Cache Directory Exists
#' @description Creates the cache directory if it doesn't exist
#' @return NULL
ensure_cache_directory <- function() {
  if (!dir.exists(CACHE_DIR)) {
    dir.create(CACHE_DIR, recursive = TRUE)
  }
}

#' @title Get File Timestamp
#' @description Retrieves the last modification time of a file
#' @param file_path Path to file
#' @return Modification time as POSIXct
get_file_timestamp <- function(file_path) {
  if (file.exists(file_path)) {
    file.info(file_path)$mtime
  } else {
    NA
  }
}

#' @title Get Pair File Path
#' @description Gets the path to the paired FASTQ file
#' @param file_path Path to one FASTQ file
#' @return Path to the paired FASTQ file
get_pair_file <- function(file_path) {
  # Extract the base name without the pair number
  base_name <- sub("_[12]\\.fastq\\.gz$", "", file_path)

  # Determine the opposite pair number
  if (grepl("_1\\.fastq\\.gz$", file_path)) {
    pair_file <- paste0(base_name, "_2.fastq.gz")
  } else if (grepl("_2\\.fastq\\.gz$", file_path)) {
    pair_file <- paste0(base_name, "_1.fastq.gz")
  } else {
    # Not a paired file, return the same path
    return(file_path)
  }

  pair_file
}

#' @title Validate Cache
#' @description Checks if the cached validation data is valid
#'   and contains all required files
#' @param cache_file Path to cache file
#' @param files Vector of file paths to validate
#' @return List with 'valid' (TRUE/FALSE) and 'problems' (list of issues)
is_cache_valid <- function(cache_file, files) {
  if (!file.exists(cache_file)) {
    return(
      list(
        valid = FALSE,
        problems = list(
          type = "no_cache",
          message = "Cache file does not exist"
        )
      )
    )
  }

  # Load cache and check if it has the expected structure
  cached_data <- fromJSON(cache_file)
  required_fields <- c(
    "file_path",
    "read_count",
    "format_valid",
    "file_timestamp",
    "file_size"
  )

  if (!all(required_fields %in% names(cached_data))) {
    return(
      list(
        valid = FALSE,
        problems = list(
          type = "invalid_structure",
          message = "Cache missing required fields"
        )
      )
    )
  }

  # Check for missing files (physical existence)
  missing_files <- character(0)

  # Check physical existence
  missing_files <- cached_data$file_path[!file.exists(cached_data$file_path)]

  # If any files are missing, cache is invalid
  if (length(missing_files) > 0) {
    return(list(
      valid = FALSE,
      problems = list(
        type = "missing_files",
        files = missing_files,
        message = "The following files are missing from disk"
      )
    ))
  }

  list(valid = TRUE, problems = list())
}

#' @title Report Cache Problems
#' @description Reports detailed information about cache problems
#' @param problems List of problems detected by is_cache_valid
#' @return NULL (aborts execution with detailed error message)
report_cache_problems <- function(problems) {
  if (problems$type == "no_cache") {
    cli::cli_abort(problems$message)
  }

  if (problems$type == "invalid_structure") {
    cli::cli_abort(problems$message)
  }

  if (problems$type == "missing_files") {
    err_msg <- paste(
      "The following files are missing:\n",
      paste(problems$files, collapse = "\n")
    )
    info_msg <- paste(
      "Manual intervention required:\n\n",
      "a) Recover the original synthetic datasets using DVC registry.\n\n",
      "b) Remove the validation cache to regenerate."
    )

    cli::cli_abort(
      c(
        "Missing files detected in validation cache.",
        "x" = err_msg,
        "i" = info_msg
      )
    )
  }
}

#' @title Update Cache
#' @description Updates cache for new and modified files in a single pass
#' @param cached_data Existing cache data
#' @param files Vector of all file paths to check
#' @return Updated cache data
update_cache <- function(cached_data, files) {
  # Detect new and modified files in one pass
  new_files <- character(0)
  modified_files <- character(0)

  for (file_path in files) {
    if (!file.exists(file_path)) next # Skip missing files

    # Check if file is new (not in cache)
    if (!file_path %in% cached_data$file_path) {
      new_files <- c(new_files, file_path)
    } else {
      # Check if existing file has been modified
      current_timestamp <- get_file_timestamp(file_path)
      cached_timestamp <- cached_data$file_timestamp[
        cached_data$file_path == file_path
      ]

      if (length(cached_timestamp) > 0 && !is.na(cached_timestamp)) {
        cached_timestamp <- as.POSIXct(cached_timestamp, origin = "1970-01-01")
        if (current_timestamp > cached_timestamp) {
          modified_files <- c(modified_files, file_path)
        }
      }
    }
  }

  # Process new files
  if (length(new_files) > 0) {
    cat("Adding", length(new_files), "new files to cache...\n")

    new_results <- mclapply(
      new_files,
      function(file_path) {
        list(
          file_path = file_path,
          read_count = count_fastq_reads(file_path),
          format_valid = validate_fastq_format(file_path),
          file_timestamp = as.character(get_file_timestamp(file_path)),
          file_size = file.size(file_path)
        )
      },
      mc.cores = detectCores() - 1
    )

    new_data <- dplyr::bind_rows(new_results)
    cached_data <- dplyr::bind_rows(cached_data, new_data)
  }

  # Process modified files
  if (length(modified_files) > 0) {
    cat("Re-validating", length(modified_files), "modified files...\n")

    modified_results <- mclapply(
      modified_files,
      function(file_path) {
        list(
          file_path = file_path,
          read_count = count_fastq_reads(file_path),
          format_valid = validate_fastq_format(file_path),
          file_timestamp = as.character(get_file_timestamp(file_path)),
          file_size = file.size(file_path)
        )
      },
      mc.cores = detectCores() - 1
    )

    # Update existing entries
    for (result in modified_results) {
      cached_data$read_count[
        cached_data$file_path == result$file_path
      ] <- result$read_count
      cached_data$format_valid[
        cached_data$file_path == result$file_path
      ] <- result$format_valid
      cached_data$file_timestamp[
        cached_data$file_path == result$file_path
      ] <- result$file_timestamp
      cached_data$file_size[
        cached_data$file_path == result$file_path
      ] <- result$file_size
    }
  }

  # Ensure cache directory exists before writing
  ensure_cache_directory()

  # Write updated cache
  write_json(cached_data, CACHE_FILE, pretty = TRUE)

  cached_data
}

#' @title Load Validation Cache
#' @description Loads or calculates validation results with intelligent caching
#' @param files Vector of file paths to validate
#' @return Data frame with validation results
load_validation_cache <- function(files) {
  # Check if cache exists and is valid
  if (file.exists(CACHE_FILE)) {
    cached_data <- fromJSON(CACHE_FILE)

    # Check if cache has required structure
    required_fields <- c(
      "file_path",
      "read_count",
      "format_valid",
      "file_timestamp",
      "file_size"
    )

    if (all(required_fields %in% names(cached_data))) {
      # Check if cache is valid (this will abort if files are missing)
      cache_validation_result <- is_cache_valid(CACHE_FILE, files)
      if (cache_validation_result$valid) {
        # Cache is valid, update for any changes
        cached_data <- update_cache(cached_data, files)
        return(cached_data)
      } else {
        # Cache is invalid, report problems
        report_cache_problems(cache_validation_result$problems)
      }
    }
  }

  # If we reach here, we need to create a new cache
  cat("Creating new validation cache for", length(files), "files...\n")

  cached_data <- mclapply(
    files,
    function(file_path) {
      list(
        file_path = file_path,
        read_count = count_fastq_reads(file_path),
        format_valid = validate_fastq_format(file_path),
        file_timestamp = as.character(get_file_timestamp(file_path)),
        file_size = file.size(file_path)
      )
    },
    mc.cores = detectCores() - 1
  )

  # Convert list to data frame
  cached_data <- dplyr::bind_rows(cached_data)

  # Ensure cache directory exists before writing
  ensure_cache_directory()

  # Write the new cache to file
  write_json(cached_data, CACHE_FILE, pretty = TRUE)

  cached_data
}

# =============================================================================
# CACHED VALIDATION FUNCTIONS
# =============================================================================

#' @title Get All FASTQ Files
#' @description Gets all FASTQ files from the dataset directory
#' @return Vector of file paths
get_all_fastq_files <- function() {
  all_files <- character(0)

  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    # Individual files
    individual_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "individual"
    )
    if (dir.exists(individual_dir)) {
      files <- list.files(
        individual_dir,
        pattern = "\\.fastq\\.gz$", full.names = TRUE
      )
      all_files <- c(all_files, files)
    }

    # Aggregated files
    aggregated_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "aggregated"
    )
    if (dir.exists(aggregated_dir)) {
      files <- list.files(
        aggregated_dir,
        pattern = "\\.fastq\\.gz$", full.names = TRUE
      )
      all_files <- c(all_files, files)
    }
  }

  all_files
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Helper function to check if datasets exist
check_datasets_exist <- function() {
  if (!dir.exists(DATASET_DIR)) {
    testthat::skip(paste0(
      "Dataset directory not found: ", DATASET_DIR,
      "\nThese tests require generated datasets. ",
      "Run data generation first or skip these tests."
    ))
  }

  # Check for at least one diversity level
  diversity_dirs <- list.dirs(
    DATASET_DIR,
    full.names = FALSE, recursive = FALSE
  )
  diversity_dirs <- diversity_dirs[grepl("_diversity$", diversity_dirs)]

  if (length(diversity_dirs) == 0) {
    testthat::skip(paste0(
      "No diversity directories found in: ", DATASET_DIR,
      "\nThese tests require generated datasets. ",
      "Run data generation first or skip these tests."
    ))
  }
}

#' @title Validate Single File.
#' @description Validates file existence, size, and gzip integrity.
#'   Uses cache when available, otherwise it falls back to direct validation.
#' @param file_path Path to FASTQ file.
#' @param cache_data Optional cached validation data.
#' @return List with validation results.
validate_single_file <- function(file_path, cache_data = NULL) {
  # If cache is provided, try to use it
  if (!is.null(cache_data)) {
    cache_row <- cache_data[cache_data$file_path == file_path, ]
    if (nrow(cache_row) > 0) {
      # Return cached validation results
      return(list(
        file_path = file_path,
        exists = TRUE, # If it's in cache, it exists
        not_empty = cache_row$file_size[1] > 0,
        # Use format validation as gzip check
        gzip_valid = cache_row$format_valid[1]
      ))
    }
  }

  # Fall back to direct validation
  # Test file exists and is accessible
  exists_check <- file.exists(file_path)

  # Test file is not empty
  size_check <- if (exists_check) file.size(file_path) > 0 else FALSE

  # Test gzip integrity
  gzip_check <- FALSE
  if (exists_check && size_check) {
    cmd <- paste("gzip -t", shQuote(file_path))
    exit_code <- system2("sh",
      args = c("-c", paste0('"', cmd, '"')),
      stdout = FALSE, stderr = FALSE
    )
    gzip_check <- exit_code == 0
  }

  list(
    file_path = file_path,
    exists = exists_check,
    not_empty = size_check,
    gzip_valid = gzip_check
  )
}

#' @title Parse Individual FASTQ Filename.
#' @description Extracts metadata from individual organism-specific
#'   FASTQ filenames.
#' @param filename Individual FASTQ filename.
#' @return Parsed metadata as a list.
parse_individual_filename <- function(filename) {
  # Expected format:
  # {organism}_{diversity}_{simulation}_{sampling_depth}_{pair}.fastq.gz
  # Example: ERR10785402_high_1_10000000_1.fastq.gz
  fn_fields <- strsplit(filename, "_")[[1]]

  if (length(fn_fields) < 5) {
    return(list(
      organism = NA_character_,
      diversity = NA_character_,
      simulation = NA_integer_,
      sampling_depth = NA_integer_,
      pair = NA_character_
    ))
  }

  list(
    organism = fn_fields[1],
    diversity = fn_fields[2],
    simulation = as.integer(fn_fields[3]),
    sampling_depth = as.integer(fn_fields[4]),
    pair = fn_fields[5]
  )
}

#' @title Parse Aggregated FASTQ Filename.
#' @description Extracts metadata from aggregated simulation FASTQ filenames.
#' @param filename Aggregated FASTQ filename.
#' @return Parsed metadata as a list.
parse_aggregated_filename <- function(filename) {
  # Expected format:
  # {diversity}_{simulation}_{sampling_depth}_{pair}.fastq.gz
  # Example: high_2_10000_2.fastq.gz
  fn_fields <- strsplit(filename, "_")[[1]]

  if (length(fn_fields) < 4) {
    return(list(
      diversity = NA_character_,
      simulation = NA_integer_,
      sampling_depth = NA_integer_,
      pair = NA_character_
    ))
  }

  list(
    diversity = fn_fields[1],
    simulation = as.integer(fn_fields[2]),
    sampling_depth = as.integer(fn_fields[3]),
    pair = fn_fields[4]
  )
}

#' @title Count FASTQ Reads.
#' @description Counts the number of reads in a gzipped FASTQ file.
#'   Uses cache when available, otherwise it falls back to direct calculation.
#' @param file_path Path to FASTQ file.
#' @param cache_data Optional cached validation data.
#' @return Number of reads.
count_fastq_reads <- function(file_path, cache_data = NULL) {
  # If cache is provided, try to use it
  if (!is.null(cache_data)) {
    cache_row <- cache_data[cache_data$file_path == file_path, ]
    if (nrow(cache_row) > 0) {
      return(cache_row$read_count[1])
    }
  }

  # Fall back to direct calculation
  # Count lines and divide by 4 to get read count
  cmd <- paste("gzip -dcf", shQuote(file_path), "| wc -l")
  lines <- as.numeric(
    system2("sh", args = c("-c", paste0('"', cmd, '"')), stdout = TRUE)
  )
  lines / 4
}

#' @title Validate FASTQ Format.
#' @description Validates FASTQ file format using simple structure checks.
#'   Uses cache when available, otherwise it falls back to direct validation.
#' @param file_path Path to FASTQ file.
#' @param cache_data Optional cached validation data.
#' @return TRUE if valid, FALSE otherwise.
validate_fastq_format <- function(file_path, cache_data = NULL) {
  # If cache is provided, try to use it
  if (!is.null(cache_data)) {
    cache_row <- cache_data[cache_data$file_path == file_path, ]
    if (nrow(cache_row) > 0) {
      return(cache_row$format_valid[1])
    }
  }

  # Fall back to direct validation
  # For small files, read everything
  # For large files, just validate the first and last few records

  # Get file size to determine if it's large
  file_size <- file.size(file_path)

  # Threshold for using sampling vs reading entire file
  # Files > 1MB use head/tail sampling for performance
  # Files <= 1MB are read entirely (fast for small files)
  LARGE_FILE_THRESHOLD <- 1000000 # 1MB

  if (file_size > LARGE_FILE_THRESHOLD) {
    # For large files, just check first and last few records
    # Read first 20 lines using head
    first_cmd <- paste("zcat", shQuote(file_path), "| head -20")
    first_lines <- system2("sh",
      args = c("-c", paste0('"', first_cmd, '"')),
      stdout = TRUE, stderr = FALSE
    )

    # Read last 20 lines using tail
    last_cmd <- paste("zcat", shQuote(file_path), "| tail -20")
    last_lines <- system2("sh",
      args = c("-c", paste0('"', last_cmd, '"')),
      stdout = TRUE, stderr = FALSE
    )

    # Combine first and last lines for validation
    lines <- c(first_lines, last_lines)
  } else {
    # For small files (<= 1MB), read everything
    # This is fast for small files and provides complete validation
    con <- gzfile(file_path, "r")
    lines <- readLines(con)
    close(con)
  }

  if (length(lines) < 4) {
    return(FALSE)
  }

  # Check that we have complete 4-line records
  if (length(lines) %% 4 != 0) {
    return(FALSE)
  }

  # Check header lines start with @
  header_lines <- lines[seq(1, length(lines), 4)]
  if (!all(grepl("^@", header_lines))) {
    return(FALSE)
  }

  # Check separator lines start with +
  separator_lines <- lines[seq(3, length(lines), 4)]
  if (!all(grepl("^\\+", separator_lines))) {
    return(FALSE)
  }

  TRUE
}

# =============================================================================
# TEST FUNCTIONS
# =============================================================================

#' Test that FASTQ files are valid and accessible
test_that("FASTQ files are valid and accessible", {
  check_datasets_exist()

  # Load validation cache for all files
  all_files <- get_all_fastq_files()
  if (length(all_files) > 0) {
    cache_data <- load_validation_cache(all_files)
  }

  # Find sample files from each diversity level
  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    individual_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "individual"
    )
    aggregated_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "aggregated"
    )

    # Test individual files
    if (dir.exists(individual_dir)) {
      files <- list.files(
        individual_dir,
        pattern = "\\.fastq\\.gz$", full.names = TRUE
      )
      if (length(files) > 0) {
        # Test individual files in parallel
        validation_results <- mclapply(
          files, validate_single_file, cache_data,
          mc.cores = detectCores() - 1
        )

        # Check results
        for (result in validation_results) {
          expect_true(
            result$exists,
            label = paste0(
              "Can't find FASTQ file.\n",
              "ℹ File path: ", result$file_path
            )
          )
          expect_true(
            result$not_empty,
            label = paste0(
              "FASTQ file must not be empty.\n",
              "ℹ File path: ", result$file_path
            )
          )
          expect_true(
            result$gzip_valid,
            label = paste0(
              "FASTQ file appears to be corrupted or incomplete.\n",
              "ℹ File path: ", result$file_path, "\n",
              "ℹ Manual intervention required: Restore from backup or DVC"
            )
          )
        }
      }
    }

    # Test aggregated files
    if (dir.exists(aggregated_dir)) {
      files <- list.files(
        aggregated_dir,
        pattern = "\\.fastq\\.gz$", full.names = TRUE
      )
      if (length(files) > 0) {
        # Test aggregated files in parallel
        validation_results <- mclapply(
          files, validate_single_file, cache_data,
          mc.cores = detectCores() - 1
        )

        # Check results
        for (result in validation_results) {
          expect_true(
            result$exists,
            label = paste0(
              "Can't find FASTQ file.\n",
              "ℹ File path: ", result$file_path
            )
          )
          expect_true(
            result$not_empty,
            label = paste0(
              "FASTQ file must not be empty.\n",
              "ℹ File path: ", result$file_path
            )
          )
          expect_true(
            result$gzip_valid,
            label = paste0(
              "FASTQ file appears to be corrupted or incomplete.\n",
              "ℹ File path: ", result$file_path, "\n",
              "ℹ Manual intervention required: Restore from backup or DVC"
            )
          )
        }
      }
    }
  }
})

#' Test FASTQ format compliance
test_that("FASTQ files follow correct format", {
  check_datasets_exist()

  # Load validation cache for all files
  all_files <- get_all_fastq_files()
  if (length(all_files) > 0) {
    cache_data <- load_validation_cache(all_files)
  }

  # Test individual files for format
  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    individual_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "individual"
    )

    if (dir.exists(individual_dir)) {
      files <- list.files(
        individual_dir,
        pattern = "\\.fastq\\.gz$", full.names = TRUE
      )

      if (length(files) > 0) {
        format_results <- mclapply(
          files, validate_fastq_format, cache_data,
          mc.cores = detectCores() - 1
        )

        for (i in seq_along(files)) {
          expect_true(
            format_results[[i]],
            label = paste0(
              "FASTQ file has invalid format.\n",
              "ℹ Format: ", format_results[[i]], "\n",
              "ℹ File path: ", files[i]
            )
          )
        }
      }
    }
  }

  # Test aggregated files for format
  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    aggregated_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "aggregated"
    )

    if (dir.exists(aggregated_dir)) {
      files <- list.files(
        aggregated_dir,
        pattern = "\\.fastq\\.gz$", full.names = TRUE
      )

      if (length(files) > 0) {
        format_results <- mclapply(
          files, validate_fastq_format, cache_data,
          mc.cores = detectCores() - 1
        )

        for (i in seq_along(files)) {
          expect_true(
            format_results[[i]],
            label = paste0(
              "FASTQ file has invalid format.\n",
              "ℹ Format: ", format_results[[i]], "\n",
              "ℹ File path: ", files[i]
            )
          )
        }
      }
    }
  }
})

#' Test paired-end consistency
test_that("Paired-end FASTQ files are consistent", {
  check_datasets_exist()

  # Load validation cache for all files
  all_files <- get_all_fastq_files()
  if (length(all_files) > 0) {
    cache_data <- load_validation_cache(all_files)
  }

  # Test individual files for paired-end consistency
  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    individual_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "individual"
    )

    if (dir.exists(individual_dir)) {
      files <- list.files(
        individual_dir,
        pattern = "\\.fastq\\.gz$", full.names = FALSE
      )

      # Group files by organism, diversity, simulation, and sampling depth
      grouping_keys <- sapply(files, function(f) {
        metadata <- parse_individual_filename(f)
        paste(metadata$organism, metadata$diversity, metadata$simulation,
          metadata$sampling_depth,
          sep = "_"
        )
      })

      file_groups <- split(files, grouping_keys)

      # Test each group has exactly 2 files (forward and reverse)
      for (group_name in names(file_groups)) {
        group_files <- file_groups[[group_name]]

        if (length(group_files) == 2) {
          # Check that one is _1 and one is _2
          pairs <- sapply(group_files, function(f) {
            parse_individual_filename(f)$pair
          })

          expect_setequal(pairs, c("1.fastq.gz", "2.fastq.gz"))

          # Check that both files have the same read count using cache
          file_paths <- file.path(individual_dir, group_files)
          read_counts <- sapply(file_paths, count_fastq_reads, cache_data)

          # Compare read count values (sapply returns named vector)
          expect_equal(
            unname(read_counts[1]),
            unname(read_counts[2]),
            label = paste0(
              "Paired-end files have different read counts.\n",
              "ℹ Group name: ", group_name, "\n",
              "ℹ Read counts (forward): ", read_counts[1], "\n",
              "ℹ Read counts (reverse): ", read_counts[2], "\n",
              "ℹ File path (forward): ", file_paths[1], "\n",
              "ℹ File path (reverse): ", file_paths[2]
            )
          )
        }
      }
    }
  }

  # Test aggregated files for paired-end consistency
  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    aggregated_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "aggregated"
    )

    if (dir.exists(aggregated_dir)) {
      files <- list.files(
        aggregated_dir,
        pattern = "\\.fastq\\.gz$", full.names = FALSE
      )

      # Group files by diversity, simulation, and sampling depth
      grouping_keys <- sapply(files, function(f) {
        metadata <- parse_aggregated_filename(f)
        paste(
          metadata$diversity, metadata$simulation, metadata$sampling_depth,
          sep = "_"
        )
      })

      file_groups <- split(files, grouping_keys)

      # Test each group has exactly 2 files (forward and reverse)
      for (group_name in names(file_groups)) {
        group_files <- file_groups[[group_name]]

        if (length(group_files) == 2) {
          # Check that one is _1 and one is _2
          pairs <- sapply(group_files, function(f) {
            parse_aggregated_filename(f)$pair
          })

          expect_setequal(pairs, c("1.fastq.gz", "2.fastq.gz"))

          # Check that both files have the same read count using cache
          file_paths <- file.path(aggregated_dir, group_files)
          read_counts <- sapply(file_paths, count_fastq_reads, cache_data)

          # Compare read count values (sapply returns named vector)
          expect_equal(unname(read_counts[1]), unname(read_counts[2]),
            label = paste0(
              "Paired-end aggregated files have different read counts.\n",
              "ℹ Group name: ", group_name, "\n",
              "ℹ Read counts (forward): ", read_counts[1], "\n",
              "ℹ Read counts (reverse): ", read_counts[2], "\n",
              "ℹ File path (forward): ", file_paths[1], "\n",
              "ℹ File path (reverse): ", file_paths[2]
            )
          )
        }
      }
    }
  }
})

#' Test aggregated file read count accuracy against filename specifications
test_that("Aggregated FASTQ files contain expected read counts", {
  check_datasets_exist()

  # Load validation cache for all files
  all_files <- get_all_fastq_files()
  if (length(all_files) > 0) {
    cache_data <- load_validation_cache(all_files)
  }

  # Test aggregated files for read count accuracy
  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    aggregated_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "aggregated"
    )

    if (dir.exists(aggregated_dir)) {
      files <- list.files(
        aggregated_dir,
        pattern = "\\.fastq\\.gz$", full.names = FALSE
      )

      if (length(files) > 0) {
        # Test ALL aggregated files for read count accuracy
        for (file in files) {
          file_path <- file.path(aggregated_dir, file)

          # Parse filename to get expected read count
          metadata <- parse_aggregated_filename(file)

          if (!is.na(metadata$sampling_depth)) {
            # Get actual reads from cache
            actual_reads <- count_fastq_reads(file_path, cache_data)

            # Should have exactly the expected number of reads
            expect_equal(
              actual_reads,
              metadata$sampling_depth,
              label = paste0(
                "Read count mismatch for aggregated file.\n",
                "ℹ Expected sampling depth: ", metadata$sampling_depth, "\n",
                "ℹ Actual sampling depth: ", actual_reads, "\n",
                "ℹ File path: ", file_path
              )
            )
          }
        }
      }
    }
  }
})

#' Test aggregated dataset structure
test_that("Aggregated datasets have correct structure", {
  check_datasets_exist()

  for (diversity in EXPECTED_DIVERSITY_LEVELS) {
    aggregated_dir <- file.path(
      DATASET_DIR, paste0(diversity, "_diversity"), "aggregated"
    )

    if (dir.exists(aggregated_dir)) {
      files <- list.files(
        aggregated_dir,
        pattern = "\\.fastq\\.gz$", full.names = FALSE
      )

      # Test filename parsing for aggregated files
      for (file in files) {
        metadata <- parse_aggregated_filename(file)

        expect_false(is.na(metadata$diversity),
          label = paste0(
            "Invalid diversity in filename.\n",
            "ℹ Diversity: ", metadata$diversity, "\n",
            "ℹ File path: ", file
          )
        )

        expect_false(is.na(metadata$simulation),
          label = paste0(
            "Invalid simulation number in filename.\n",
            "ℹ Simulation: ", metadata$simulation, "\n",
            "ℹ File path: ", file
          )
        )

        expect_false(is.na(metadata$sampling_depth),
          label = paste0(
            "Invalid sampling depth in filename.\n",
            "ℹ Sampling depth: ", metadata$sampling_depth, "\n",
            "ℹ File path: ", file
          )
        )

        # Test that diversity matches directory name
        expect_equal(metadata$diversity, diversity,
          label = paste0(
            "Diversity mismatch in filename.\n",
            "ℹ Expected diversity: ", diversity, "\n",
            "ℹ Actual diversity: ", metadata$diversity, "\n",
            "ℹ File path: ", file
          )
        )
      }
    }
  }
})


# Run all tests
if (!require(testthat)) {
  cat(
    "testthat package not available. Install with: ",
    "install.packages('testthat')\n"
  )
}
