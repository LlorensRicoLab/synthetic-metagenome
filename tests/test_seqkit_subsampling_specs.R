#!/usr/bin/env Rscript

#' @title Test SeqKit Command File Consistency
#' @description Verifies that seqkit command files maintain expected structure
#' and content across different read counts and refactoring changes.
#' @author Francisco Merino-Casallo
#' @date 2025-06-25

# Load required libraries
suppressPackageStartupMessages({
  library(tidyverse)
  library(testthat)
  library(here)
})

# Set up test context
context("SeqKit Subsampling Specification File Consistency Tests")

# Test configuration
SEQKIT_FNS <- c(
  here(
    "data/synthetic/generation/syn_specs/seqkit_subsampling_specs_1e+04.txt"
  ),
  here(
    "data/synthetic/generation/syn_specs/seqkit_subsampling_specs_1e+05.txt"
  ),
  here(
    "data/synthetic/generation/syn_specs/seqkit_subsampling_specs_1e+06.txt"
  ),
  here(
    "data/synthetic/generation/syn_specs/seqkit_subsampling_specs_1e+07.txt"
  )
)

# Expected patterns and structure
EXPECTED_READ_COUNTS <- c(10000, 100000, 1000000, 10000000)
EXPECTED_DIV_LVLS <- c("low", "mid", "high")
EXPECTED_SIMS_PER_DIV_LEVEL <- 5
# Structure: 4 sampling depths × 3 diversity levels × 5 simulations
# 60 total datasets
EXPECTED_TOTAL_DATASETS <- (
  length(EXPECTED_READ_COUNTS) *
    length(EXPECTED_DIV_LVLS) *
    EXPECTED_SIMS_PER_DIV_LEVEL
)

# Helper function to check if SeqKit files exist
check_seqkit_files_exist <- function() {
  missing_files <- c()
  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      missing_files <- c(missing_files, basename(fn))
    }
  }

  if (length(missing_files) > 0) {
    testthat::skip(
      paste0(
        "SeqKit command files not found: ",
        paste(missing_files, collapse = ", "),
        "\nThese files are managed by DVC. ",
        "Run 'dvc pull data/synthetic/generation/syn_specs.dvc' ",
        "to download them before running these tests."
      )
    )
  }
  # Silent on success
}

#' Parse seqkit subsampling specification file
#' @param spec A single specification from seqkit subsampling specification file
#' @return Parsed components as a list
parse_seqkit_spec <- function(spec) {
  params <- strsplit(spec, " ")[[1]]
  if (length(params) != 4) {
    stop("Invalid seqkit command format: ", spec)
  }

  list(
    input_fn = params[1],
    seed = as.integer(params[2]),
    read_count = as.integer(params[3]),
    output_fn = params[4]
  )
}

#' Extract a specific field from the output filename
#' @param output_fn Output filename from seqkit command
#' @param field 'run', 'diversity', 'simulation', 'sampling_depth', or 'pair'
#' @return The requested field (character or integer)
extract_from_filename <- function(
    output_fn,
    field = c("run", "diversity", "simulation", "sampling_depth", "pair")) {
  field <- match.arg(field)

  # Expected format:
  # {diversity}_diversity/individual/{organism}_{diversity}_{simulation}_
  # {sampling_depth}_{pair}.fastq.gz
  # For example: mid_diversity/individual/ERR10785402_mid_1_10000_1.fastq.gz
  fields <- strsplit(output_fn, "/")[[1]]
  if (length(fields) != 3) {
    stop("Invalid output filename format: ", output_fn)
  }

  # Extract diversity from the first part: {diversity}_diversity
  diversity_part <- fields[1]
  diversity <- strsplit(diversity_part, "_")[[1]][1]

  # Extract filename from the third part:
  # {organism}_{diversity}_{simulation}_{sampling_depth}_{pair}.fastq.gz
  fn <- fields[3]
  fn_fields <- strsplit(fn, "_")[[1]]
  if (length(fn_fields) < 5) {
    stop("Invalid filename format: ", fn)
  }

  switch(field,
    run = fn_fields[1], # organism (e.g., ERR10785402)
    diversity = diversity, # from directory name
    simulation = as.integer(fn_fields[3]),
    sampling_depth = as.integer(fn_fields[4]),
    pair = fn_fields[5]
  )
}

#' Test that all seqkit subsampling specification files exist
test_that("All seqkit subsampling specification files exist", {
  missing_files <- c()
  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      missing_files <- c(missing_files, basename(fn))
    }
  }

  if (length(missing_files) > 0) {
    testthat::skip(
      paste0(
        "SeqKit subsampling specification file(s) not found: ",
        paste(missing_files, collapse = ", "),
        "\nThese files are managed by DVC. ",
        "Run 'dvc pull data/synthetic/generation/syn_specs.dvc' ",
        "to download them before running these tests."
      )
    )
  }
  # If we reach here, all files exist - verify this explicitly
  for (fn in SEQKIT_FNS) {
    expect_true(file.exists(fn),
      label = paste0("File should exist: ", basename(fn))
    )
  }
  # Silent on success
})

#' Test file structure and format
test_that("Seqkit subsampling specification files have correct structure", {
  check_seqkit_files_exist()

  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    expect_gt(length(specs), 0,
      label = paste0("Empty file: ", fn)
    )

    # Test each subsampling specification format (line by line)
    for (spec in specs) {
      expect_no_error(
        parse_seqkit_spec(spec)
      )
    }
  }
})

#' Test read count consistency across simulations
test_that("Total read counts per simulation equal expected sampling depths", {
  check_seqkit_files_exist()

  for (i in seq_along(SEQKIT_FNS)) {
    fn <- SEQKIT_FNS[i]
    expected_sampling_depth <- EXPECTED_READ_COUNTS[i]

    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    parsed_specs <- lapply(specs, parse_seqkit_spec)

    # Group specifications by simulation (diversity + simulation)
    # to handle paired reads correctly
    simulation_groups <- split(
      parsed_specs,
      sapply(parsed_specs, function(spec) {
        paste(
          extract_from_filename(spec$output_fn, "diversity"),
          extract_from_filename(spec$output_fn, "simulation"),
          sep = "_"
        )
      })
    )

    # For each simulation, verify read count consistency
    for (group_name in names(simulation_groups)) {
      group <- simulation_groups[[group_name]]

      # Sum read counts for all organisms in this simulation
      # (taking only forward reads to avoid double-counting)
      total_read_counts <- sum(sapply(group, function(spec) {
        if (extract_from_filename(spec$output_fn, "pair") == "1.fastq.gz") {
          spec$read_count
        } else {
          0
        }
      }))

      # Verify total read counts equal expected sampling depth
      expect_equal(
        total_read_counts,
        expected_sampling_depth,
        label = paste0(
          "Simulation ", group_name,
          " read count doesn't match expected sampling depth in ", fn,
          " - expected: ", expected_sampling_depth,
          " - actual: ", total_read_counts
        )
      )

      # Verify that forward and reverse files have the same read count
      # for each organism (if paired reads exist)
      if (length(group) == 2) {
        forward_organism_reads <- group[[1]]$read_count
        reverse_organism_reads <- group[[2]]$read_count
        expect_equal(
          forward_organism_reads,
          reverse_organism_reads,
          label = paste0(
            "Forward and reverse organism read counts differ for simulation ",
            group_name, " in ", fn,
            " - forward: ", forward_organism_reads,
            ", reverse: ", reverse_organism_reads
          )
        )
      }
    }

    # Also check that each organism includes a positive read count
    for (spec in parsed_specs) {
      expect_gt(
        spec$read_count,
        0,
        label = paste0("Non-positive organism read count in ", fn)
      )
    }
  }
})

#' Test that all expected diversity levels are present
test_that("All expected diversity levels are present", {
  check_seqkit_files_exist()

  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    parsed_specs <- lapply(specs, parse_seqkit_spec)

    # Extract unique diversity levels from output filenames
    diversities <- unique(sapply(parsed_specs, function(spec) {
      extract_from_filename(spec$output_fn, "diversity")
    }))

    # Should have exactly the expected diversity levels
    expect_setequal(diversities, EXPECTED_DIV_LVLS)
  }
})

#' Test that each diversity level has the expected number of simulations
test_that("Each diversity level has expected number of simulations", {
  check_seqkit_files_exist()

  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    parsed_specs <- lapply(specs, parse_seqkit_spec)

    # Extract diversity and simulation information
    diversity_simulations <- sapply(parsed_specs, function(spec) {
      paste(
        extract_from_filename(spec$output_fn, "diversity"),
        extract_from_filename(spec$output_fn, "simulation"),
        sep = "_"
      )
    })

    # Count simulations per diversity level
    for (diversity in EXPECTED_DIV_LVLS) {
      unique_simulations <- unique(
        diversity_simulations[
          grepl(paste0("^", diversity, "_"), diversity_simulations)
        ]
      )

      expect_equal(
        length(unique_simulations),
        EXPECTED_SIMS_PER_DIV_LEVEL,
        label = paste(
          "Expected", EXPECTED_SIMS_PER_DIV_LEVEL,
          "simulations for", diversity, "diversity, got",
          length(unique_simulations), "in", fn
        )
      )
    }
  }
})

#' Test paired read consistency
test_that("Paired reads are properly matched", {
  check_seqkit_files_exist()

  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    parsed_specs <- lapply(specs, parse_seqkit_spec)

    # Group by run, diversity, and simulation
    organism_groups <- split(parsed_specs, sapply(parsed_specs, function(spec) {
      paste(
        extract_from_filename(spec$output_fn, "run"),
        extract_from_filename(spec$output_fn, "diversity"),
        extract_from_filename(spec$output_fn, "simulation"),
        sep = "_"
      )
    }))

    # Each group should have exactly 2 entries (paired reads)
    for (group_name in names(organism_groups)) {
      group <- organism_groups[[group_name]]
      expect_equal(
        length(group), 2,
        label = paste0(
          "Paired read mismatch for organism ", group_name, " in ", fn
        )
      )

      # Check that one is _1 and one is _2
      pairs <- sapply(group, function(spec) {
        extract_from_filename(spec$output_fn, "pair")
      })
      expect_setequal(pairs, c("1.fastq.gz", "2.fastq.gz"))
    }
  }
})

#' Test seed format (but not specific values)
test_that("Seeds are valid integers within reasonable range", {
  check_seqkit_files_exist()

  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    parsed_specs <- lapply(specs, parse_seqkit_spec)

    # Check that seeds are positive integers
    for (spec in parsed_specs) {
      seed <- spec$seed
      expect_true(
        is.integer(seed) && seed > 0 && seed <= 200,
        label = paste0("Invalid seed value in ", fn, ": ", seed)
      )
    }
  }
})

#' Test unique synthetic simulation count
test_that("Correct number of unique synthetic simulations", {
  check_seqkit_files_exist()

  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    parsed_specs <- lapply(specs, parse_seqkit_spec)

    # Extract unique simulations from output filenames
    # (diversity + simulation combinations)
    unique_simulations <- unique(sapply(parsed_specs, function(spec) {
      paste(
        extract_from_filename(spec$output_fn, "diversity"),
        extract_from_filename(spec$output_fn, "simulation"),
        sep = "_"
      )
    }))

    # Should have exactly the expected number of unique simulations per file
    # (3 diversity levels × 5 simulations = 15 simulations per sampling depth)
    expected_simulations_per_file <- (
      length(EXPECTED_DIV_LVLS)
      * EXPECTED_SIMS_PER_DIV_LEVEL
    )
    expect_equal(
      length(unique_simulations),
      expected_simulations_per_file,
      label = paste(
        "Expected", expected_simulations_per_file, "unique simulations, got",
        length(unique_simulations), "in", fn
      )
    )
  }
})

#' Test that organism-specific input files for SeqKit's subsampling exist
#' and are accessible
test_that("Organism-specific input files for SeqKit's subsampling exist", {
  check_seqkit_files_exist()

  for (fn in SEQKIT_FNS) {
    if (!file.exists(fn)) {
      testthat::skip(paste0("File not found: ", fn))
    }

    specs <- readLines(fn)
    parsed_specs <- lapply(specs, parse_seqkit_spec)

    # Check that each referenced organism-specific input file exists
    for (spec in parsed_specs) {
      input_file_path <- here(
        "data", "synthetic", "generation", "source_fastq",
        spec$input_fn
      )

      expect_true(
        file.exists(input_file_path),
        label = paste0(
          "Organism-specific input file not found: ", input_file_path
        )
      )
    }
  }
})

## Run all tests
if (!require(testthat)) {
  cat(
    "testthat package not available. Install with: ",
    "install.packages('testthat')\n"
  )
}
