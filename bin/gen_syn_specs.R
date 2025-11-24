#!/usr/bin/env Rscript

#' @title Synthetic Metatranscriptome Dataset Generator
#' @author Verónica Lloréns Rico
#' @author Francisco Merino-Casallo
#' @date 2025-07-31
#' @description Generates synthetic metatranscriptome datasets
#' with controlled diversity levels
#'
#' @details Creates synthetic metatranscriptomes
#' by subsampling public RNA-seq data.
#' Produces datasets with controlled diversity levels and sampling depths,
#' ensuring read availability constraints are met.
#'
#' @usage Rscript gen_syn_specs.R
#' --sims-per-ecology 200 --sims-per-diversity 5 --output-dir syn_specs/
#' --seed 42

# ============================================================================
# SETUP AND DEPENDENCIES
# ============================================================================

# Load required libraries
suppressPackageStartupMessages({
  library(tidyverse)
  library(ggpubr)
  library(optparse)
  library(here)
  library(jsonlite)
  library(future)
  library(furrr)
  library(vegan)
  library(stringr)
  library(grid)
  library(khroma)
  library(cli)
  library(rlang)
})

options(scipen = 999)

# Make .data pronoun visible to lintr
# This prevents "no visible binding for global variable" warnings
# when using dplyr's .data pronoun in NSE contexts
# Equivalent to @importFrom rlang .data in packages
.data <- rlang::.data

# ============================================================================
# CONSTANTS
# ============================================================================

# Sampling depths for synthetic dataset generation: read counts to simulate
SAMPLING_DEPTHS <- c(10^4, 10^5, 10^6, 10^7)

# Random seed range for subsampling commands
RND_SEED_RANGE <- 1:200

# File paths
SRA_MAPPING_FILE <- here(
  "data", "mapping", "run_organism_map.csv"
)
ABUNDANCE_DIR <- here("data", "abundance")
SOURCE_FASTQ_DIR <- here("data", "source_fastq")
CACHE_DIR <- here("data", "cache")
CACHE_FILE <- file.path(CACHE_DIR, "available_reads_cache.json")

# ============================================================================
# CACHE DIRECTORY MANAGEMENT
# ============================================================================

#' @title Ensure Cache Directory Exists
#' @description Creates the cache directory if it doesn't exist
#' @return NULL
ensure_cache_directory <- function() {
  if (!dir.exists(CACHE_DIR)) {
    dir.create(CACHE_DIR, recursive = TRUE)
  }
}

# ============================================================================
# CONFIGURATION AND CLI
# ============================================================================

#' @title Parse Command Line Arguments
#' @description Parses and validates command line arguments
#' for the synthetic dataset generator
#' @return Parsed command line arguments
parse_cli_arguments <- function() {
  option_list <- list(
    optparse::make_option(c("--sims-per-ecology"),
      type = "integer", default = 200,
      help = "Number of simulations per ecology state [default: %default]"
    ),
    optparse::make_option(c("--sims-per-diversity"),
      type = "integer", default = 5,
      help = "Number of simulations per diversity level [default: %default]"
    ),
    optparse::make_option(c("--output-dir"),
      type = "character",
      default = here("data", "syn_specs"),
      help = "Output directory [default: %default]"
    ),
    optparse::make_option(c("--seed"),
      type = "integer", default = 42,
      help = "Random seed for reproducibility [default: %default]"
    ),
    optparse::make_option(c("--no-plots"),
      action = "store_true", default = FALSE,
      help = "Disable plot generation [default: %default]"
    )
  )

  opt_parser <- optparse::OptionParser(option_list = option_list)
  optparse::parse_args(opt_parser)
}

#' @title Initialize System Configuration
#' @description Sets up system configuration
#' including random seed, parallel processing, and file paths
#' @param opt Parsed command line arguments
#' @return List of configuration parameters
initialize_configuration <- function(opt) {
  # Set random seed
  set.seed(opt$seed)

  # Configure parallel processing
  # I run multiple executions of the script with different values
  # for n_workers to get the best performance. 8 workers was the best for me.
  n_cores <- parallel::detectCores()
  n_workers <- min(ceiling(n_cores * 0.5), 8)
  future::plan(future::multisession, workers = n_workers)

  # File paths
  config <- list(
    run_mapping_file = SRA_MAPPING_FILE,
    abundance_dir = ABUNDANCE_DIR,
    output_dir = opt$`output-dir`,
    source_fastq_dir = SOURCE_FASTQ_DIR,
    cache_file = CACHE_FILE,
    n_sims_per_ecology_state = opt$`sims-per-ecology`,
    n_sims_per_diversity_level = opt$`sims-per-diversity`,
    sampling_depths = SAMPLING_DEPTHS,
    no_plots = opt$`no-plots`
  )

  # Create output directory if it doesn't exist
  if (!dir.exists(config$output_dir)) {
    dir.create(config$output_dir, recursive = TRUE)
  }

  if (!config$no_plots && !dir.exists(file.path(config$output_dir, "plots"))) {
    dir.create(file.path(config$output_dir, "plots"), recursive = TRUE)
  }

  config
}

# ============================================================================
# DATA LOADING FUNCTIONS
# ============================================================================

#' @title Load Organism Mapping Data
#' @description Loads the organism mapping data from CSV file
#' @param config Configuration parameters
#' @return Data frame with organism mapping information
load_organism_mapping <- function(config) {
  run_organism_map <- readr::read_csv(
    config$run_mapping_file,
    show_col_types = FALSE
  )

  run_organism_map
}

#' @title Load Abundance Data
#' @description Loads and parses abundance files from the specified directory,
#' extracting ecology state information from filenames
#' @param abundance_dir Directory containing abundance files
#' @return List of abundance data objects,
#' each containing abundance matrix and eco_state
get_abundance_data <- function(abundance_dir) {
  if (!dir.exists(abundance_dir)) {
    stop(paste("Abundance directory not found:", abundance_dir))
  }

  abundance_files <- list.files(abundance_dir, full.names = FALSE)
  if (length(abundance_files) == 0) {
    stop(paste("No abundance files found in:", abundance_dir))
  }

  # Pre-read all abundance files
  abundance_data <- purrr::map(abundance_files, function(filename) {
    abundance <- read.table(
      file.path(abundance_dir, filename),
      header = TRUE, sep = "\t", stringsAsFactors = FALSE
    )
    eco_state <- strsplit(filename, split = "[[:punct:]]")[[1]][5]

    # Validate eco_state extraction
    if (is.na(eco_state) || eco_state == "") {
      cli::cli_alert_warning(
        "Could not extract eco_state from filename: {filename}"
      )
    }

    list(abundance = abundance, eco_state = eco_state)
  })

  abundance_data
}

# ============================================================================
# ORGANISM-SPECIFIC READS AVAILABILITY AND CACHING
# ============================================================================

#' @title Validate FASTQ File Pair
#' @description Validates that both forward and reverse FASTQ files exist
#' @param fastq_forward_file Path to forward FASTQ file
#' @param fastq_reverse_file Path to reverse FASTQ file
#' @return NULL (stops execution if validation fails)
validate_fastq_pair <- function(fastq_forward_file, fastq_reverse_file) {
  if (!file.exists(fastq_forward_file)) {
    stop(
      paste(
        "FATAL ERROR: Forward FASTQ file missing:",
        fastq_forward_file,
        "\n  Paired-end sequencing requires both forward and reverse files.",
        "\n  Execution stopped to prevent generating invalid synthetic data."
      )
    )
  }

  if (!file.exists(fastq_reverse_file)) {
    stop(
      paste(
        "FATAL ERROR: Reverse FASTQ file missing:",
        fastq_reverse_file,
        "\n  Paired-end sequencing requires both forward and reverse files.",
        "\n  Execution stopped to prevent generating invalid synthetic data."
      )
    )
  }
}

#' @title Get File Timestamp
#' @description Retrieves the modification time
#' of both forward and reverse FASTQ files
#' @param fastq_forward_file Path to forward FASTQ file
#' @param fastq_reverse_file Path to reverse FASTQ file
#' @return List with forward_mtime and reverse_mtime
get_file_timestamp <- function(fastq_forward_file, fastq_reverse_file) {
  # Files are already validated by validate_fastq_pair,
  # so we can just get timestamps
  list(
    forward_mtime = file.info(fastq_forward_file)$mtime,
    reverse_mtime = file.info(fastq_reverse_file)$mtime
  )
}

#' @title Count FASTQ Reads
#' @description Counts the number of reads
#' in both forward and reverse FASTQ files and validates they are identical
#' @param fastq_forward_file Path to forward FASTQ file
#' @param fastq_reverse_file Path to reverse FASTQ file
#' @return Number of reads (both files must have identical counts)
get_fastq_read_count <- function(fastq_forward_file, fastq_reverse_file) {
  # Files are already validated by validate_fastq_pair,
  # so we can just count reads
  cmd <- paste("gzip -dcf", shQuote(fastq_forward_file), "| wc -l")
  forward_lines <- as.numeric(
    system2("sh", args = c("-c", paste0('"', cmd, '"')), stdout = TRUE)
  )
  forward_read_count <- forward_lines / 4

  cmd <- paste("gzip -dcf", shQuote(fastq_reverse_file), "| wc -l")
  reverse_lines <- as.numeric(
    system2("sh", args = c("-c", paste0('"', cmd, '"')), stdout = TRUE)
  )
  reverse_read_count <- reverse_lines / 4

  if (forward_read_count != reverse_read_count) {
    stop(
      paste(
        "FATAL ERROR: Read count mismatch:",
        "\n  Forward file:", fastq_forward_file,
        "\n  Reverse file:", fastq_reverse_file,
        "\n  Forward reads:", forward_read_count,
        "\n  Reverse reads:", reverse_read_count,
        "\n  This indicates corrupted or invalid paired-end sequencing data.",
        "\n  Execution stopped to prevent generating invalid synthetic data."
      )
    )
  }

  forward_read_count
}

#' @title Validate Cache
#' @description Checks if the cached read count data is valid
#' and contains all required run accessions
#' @param cache_file Path to cache file
#' @param run_accessions Vector of run accession identifiers
#' @return TRUE if cache is valid, FALSE otherwise
is_cache_valid <- function(cache_file, run_accessions) {
  if (!file.exists(cache_file)) {
    return(FALSE)
  }

  # Load cache and check if it has the expected structure
  cached_data <- fromJSON(cache_file)
  required_fields <- c(
    "run_accession", "available_reads", "forward_timestamp", "reverse_timestamp"
  )

  if (!all(required_fields %in% names(cached_data))) {
    return(FALSE)
  }

  # Check if all expected runs are present
  if (!all(run_accessions %in% cached_data$run_accession)) {
    return(FALSE)
  }

  TRUE
}

#' @title Get Changed File Pairs
#' @description Identifies FASTQ file pairs
#' that have been modified since last cache update
#' @param cache_file Path to cache file
#' @param run_accessions Vector of run accession identifiers
#' @param source_fastq_dir Directory containing FASTQ files
#' @return List of file pairs
#' (each pair contains forward and reverse file paths)
get_changed_file_pairs <- function(
  cache_file, run_accessions, source_fastq_dir
) {
  if (!file.exists(cache_file)) {
    # If the cache file does not exist, return file pairs for all runs
    # since we don't have any information about the files and its content.
    return(purrr::map(run_accessions, function(run_accession) {
      list(
        forward = file.path(
          source_fastq_dir, paste0(run_accession, "_1.fastq.gz")
        ),
        reverse = file.path(
          source_fastq_dir, paste0(run_accession, "_2.fastq.gz")
        )
      )
    }))
  }

  cached_data <- fromJSON(cache_file)
  cached_data$forward_timestamp <- as.POSIXct(
    cached_data$forward_timestamp,
    origin = "1970-01-01"
  )

  cached_data$reverse_timestamp <- as.POSIXct(
    cached_data$reverse_timestamp,
    origin = "1970-01-01"
  )

  # Pre-allocate list for better performance
  changed_file_pairs <- vector("list", length(run_accessions))
  count <- 0

  for (run_accession in run_accessions) {
    fastq_forward_file <- file.path(
      source_fastq_dir, paste0(run_accession, "_1.fastq.gz")
    )
    fastq_reverse_file <- file.path(
      source_fastq_dir, paste0(run_accession, "_2.fastq.gz")
    )

    # Validate files first
    validate_fastq_pair(fastq_forward_file, fastq_reverse_file)

    # Get timestamps of the latest modification time of the files
    timestamps <- get_file_timestamp(fastq_forward_file, fastq_reverse_file)
    forward_mtime <- timestamps$forward_mtime
    reverse_mtime <- timestamps$reverse_mtime

    cached_forward_timestamp <- cached_data$forward_timestamp[
      cached_data$run_accession == run_accession
    ]

    cached_reverse_timestamp <- cached_data$reverse_timestamp[
      cached_data$run_accession == run_accession
    ]

    # Check if we need to update the cache for this run
    # based on the latest modification timestamps.
    if (
      (length(cached_forward_timestamp) == 0) ||
        (is.na(cached_forward_timestamp)) ||
        (forward_mtime > cached_forward_timestamp) ||
        (length(cached_reverse_timestamp) == 0) ||
        (is.na(cached_reverse_timestamp)) ||
        (reverse_mtime > cached_reverse_timestamp)
    ) {
      count <- count + 1
      changed_file_pairs[[count]] <- list(
        forward = fastq_forward_file,
        reverse = fastq_reverse_file
      )
    }
  }

  # Return only the used portion of the list
  if (count == 0) {
    list() # Return empty list
  } else {
    changed_file_pairs[1:count] # Return only used elements
  }
}

#' @title Get Available Reads
#' @description Loads or calculates available reads per run
#' with intelligent caching to avoid redundant computations
#' @param config Configuration parameters
#' @param run_organism_map Organism mapping data
#' @return Data frame with available reads information
load_available_reads <- function(config, run_organism_map) {
  # Check if the cache is valid.
  if (is_cache_valid(config$cache_file, run_organism_map$run_accession)) {
    available_reads <- fromJSON(config$cache_file)
    available_reads$forward_timestamp <- as.POSIXct(
      available_reads$forward_timestamp,
      origin = "1970-01-01"
    )
    available_reads$reverse_timestamp <- as.POSIXct(
      available_reads$reverse_timestamp,
      origin = "1970-01-01"
    )

    # Check if there are any changed files since the last cache update.
    changed_file_pairs <- get_changed_file_pairs(
      config$cache_file,
      run_organism_map$run_accession,
      config$source_fastq_dir
    )

    # If there are any changed files, we need to update the cache.
    if (length(changed_file_pairs) > 0) {
      # Get run accessions for changed files
      changed_run_accessions <- purrr::map_chr(
        changed_file_pairs,
        function(file_pair) {
          # Extract run accession from forward file path
          basename(file_pair$forward) %>%
            stringr::str_replace("_1\\.fastq\\.gz$", "")
        }
      )

      # Get the current number of reads for each changed file.
      new_counts <- furrr::future_map_dbl(
        changed_file_pairs,
        ~ get_fastq_read_count(.x$forward, .x$reverse)
      )

      # Get the current latest modification timestamps of the changed files.
      new_timestamps <- furrr::future_map(
        changed_file_pairs,
        ~ get_file_timestamp(.x$forward, .x$reverse)
      )

      # Update the cache with the new information.
      for (i in seq_along(changed_file_pairs)) {
        run_accession <- changed_run_accessions[i]
        available_reads$available_reads[
          available_reads$run_accession == run_accession
        ] <- new_counts[i]
        available_reads$forward_timestamp[
          available_reads$run_accession == run_accession
        ] <- new_timestamps[[i]]$forward_mtime
        available_reads$reverse_timestamp[
          available_reads$run_accession == run_accession
        ] <- new_timestamps[[i]]$reverse_mtime
      }

      # Ensure cache directory exists before writing
      ensure_cache_directory()

      # Write the updated cache to file.
      write_json(available_reads, config$cache_file, pretty = TRUE)
    }
  } else {
    # If the cache is not valid, we need to (re)create it.

    # Get the latest modification timestamps of the files.
    new_timestamps <- furrr::future_map(
      run_organism_map$run_accession,
      ~ get_file_timestamp(
        file.path(config$source_fastq_dir, paste0(.x, "_1.fastq.gz")),
        file.path(config$source_fastq_dir, paste0(.x, "_2.fastq.gz"))
      )
    )

    # Get the number of reads for each run.
    available_reads <- tibble::tibble(
      run_accession = run_organism_map$run_accession,
      available_reads = furrr::future_map_dbl(
        run_organism_map$run_accession,
        ~ get_fastq_read_count(
          file.path(config$source_fastq_dir, paste0(.x, "_1.fastq.gz")),
          file.path(config$source_fastq_dir, paste0(.x, "_2.fastq.gz"))
        )
      ),
      forward_timestamp = purrr::map_dbl(new_timestamps, ~ .x$forward_mtime),
      reverse_timestamp = purrr::map_dbl(new_timestamps, ~ .x$reverse_mtime)
    )

    # Ensure cache directory exists before writing
    ensure_cache_directory()

    # Write the new cache to file.
    write_json(available_reads, config$cache_file, pretty = TRUE)
  }

  available_reads %>%
    dplyr::select(dplyr::all_of(c("run_accession", "available_reads")))
}

# ============================================================================
# SIMULATIONS SPECIFICATIONS GENERATION
# ============================================================================

#' @title Generate Simulation Specifications
#' @description Creates simulation specifications
#' by sampling from abundance matrices for different ecology states
#' @param config Configuration parameters
#' @param run_organism_map Organism mapping data
#' @return Data frame with simulation specifications
gen_sim_specs <- function(config, run_organism_map) {
  # Load abundance data
  abundance_data <- get_abundance_data(config$abundance_dir)

  # Create all combinations
  all_combinations <- tidyr::expand_grid(
    file_index = seq_along(abundance_data),
    sim_number = seq_len(config$n_sims_per_ecology_state)
  )

  # Process all combinations
  sims_specs <- purrr::map_dfr(seq_len(nrow(all_combinations)), function(i) {
    file_idx <- all_combinations$file_index[i]
    sim_number <- all_combinations$sim_number[i]

    current_file <- abundance_data[[file_idx]]
    abundance <- current_file$abundance
    eco_state <- current_file$eco_state

    # Sample organisms and samples
    selected_organisms <- sample(
      rownames(abundance),
      replace = FALSE,
      size = nrow(run_organism_map)
    )
    selected_sample <- sample(colnames(abundance), replace = FALSE, size = 1)
    raw_reads <- abundance[selected_organisms, selected_sample]

    # Create a tibble with the simulation most basic specifications
    # and calculate the associated sampled diversity (based on Simpson's index)
    # and diversity level (low, mid, high).
    # We'll end up with a specific number of simulations per diversity level.
    tibble::tibble(
      abs_abundance = raw_reads,
      organism = run_organism_map$organism,
      eco_state = eco_state,
      sim_number = sim_number,
      rel_abundance = raw_reads / sum(raw_reads),
      diversity = vegan::diversity(raw_reads, index = "simpson")
    ) %>%
      dplyr::mutate(
        diversity_level = factor(
          dplyr::case_when(
            .data$diversity < 0.5 ~ "low",
            .data$diversity < 0.75 ~ "mid",
            TRUE ~ "high"
          ),
          levels = c("low", "mid", "high")
        )
      )
  }, .id = NULL)

  sims_specs
}

# ============================================================================
# READ COUNT GENERATION
# ============================================================================

#' @title Generate Read Counts
#' @description Generates read count distributions
#' for different sequencing depths using proportional scaling
#' @param sims_specs Simulation specifications
#' @param sampling_depths Vector of sampling depths
#' @return Data frame with read count results
gen_read_counts <- function(sims_specs, sampling_depths) {
  # Get the minimum sampling depth to use as base
  min_sampling_depth <- min(sampling_depths)

  # Generate base read counts for the minimum sampling depth
  base_read_counts <- sims_specs %>%
    dplyr::select(
      dplyr::all_of(c("eco_state", "sim_number", "organism", "rel_abundance"))
    ) %>%
    dplyr::group_by(
      dplyr::across(c("eco_state", "sim_number"))
    ) %>%
    dplyr::mutate(
      base_num_reads_per_organism = as.vector(
        rmultinom(
          1,
          size = min_sampling_depth,
          prob = .data$rel_abundance
        )
      )
    ) %>%
    dplyr::ungroup() %>%
    dplyr::select(
      dplyr::all_of(
        c("eco_state", "sim_number", "organism", "base_num_reads_per_organism")
      )
    )

  # Generate proportional read counts for all sampling depths
  read_count_results <- purrr::map_dfr(
    sampling_depths,
    function(sampling_depth) {
      base_read_counts %>%
        dplyr::mutate(
          num_reads_per_organism = as.integer(round(
            .data$base_num_reads_per_organism *
              (sampling_depth / min_sampling_depth)
          )),
          sampling_depth = sampling_depth
        ) %>%
        dplyr::select(
          dplyr::all_of(
            c(
              "eco_state", "sim_number", "organism",
              "num_reads_per_organism", "sampling_depth"
            )
          )
        )
    },
    .id = NULL
  )

  # Adds sampling depth and read counts to the simulation specifications.
  sims_specs_with_reads <- sims_specs %>%
    dplyr::inner_join(
      read_count_results,
      by = c("eco_state", "sim_number", "organism")
    ) %>%
    # Ensure all original columns are preserved
    dplyr::select(
      dplyr::all_of(
        c(
          "eco_state", "sim_number", "organism",
          "abs_abundance", "rel_abundance",
          "diversity", "diversity_level",
          "num_reads_per_organism", "sampling_depth"
        )
      )
    )

  sims_specs_with_reads
}

# ============================================================================
# VALIDITY FILTERING
# ============================================================================

#' @title Filter Valid Simulations
#' @description Filters simulations
#' to ensure they don't exceed available reads for any organism
#' @param sims_specs_with_reads Simulations with read counts
#' @param run_organism_map Organism mapping data
#' @param available_reads Available reads data
#' @return List with valid simulations and validity information
filter_valid_sims <- function(
  sims_specs_with_reads, run_organism_map, available_reads
) {
  # Add run_accession and available_reads to the simulation specifications.
  sims_specs_with_reads <- sims_specs_with_reads %>%
    dplyr::left_join(run_organism_map, by = "organism") %>%
    dplyr::left_join(available_reads, by = "run_accession")

  # Check if we have enough reads to generate the simulations.
  # We will discard simulations that require more reads than available.
  sim_validity <- sims_specs_with_reads %>%
    dplyr::mutate(
      exceeds = .data$num_reads_per_organism > .data$available_reads
    ) %>%
    dplyr::group_by(
      dplyr::across(c("eco_state", "sim_number", "sampling_depth"))
    ) %>%
    dplyr::summarize(
      is_valid = !any(
        .data$exceeds |
          is.na(.data$num_reads_per_organism) |
          is.na(.data$available_reads)
      ),
      limiting_organism = paste(.data$organism[.data$exceeds], collapse = ", "),
      .groups = "drop"
    )

  # Add reads-associated validity information to the simulation specifications.
  sims_specs_with_reads <- sims_specs_with_reads %>%
    dplyr::left_join(
      sim_validity,
      by = c("eco_state", "sim_number", "sampling_depth")
    )

  # Discard simulations that require more reads than available.
  sims_specs_valid <- sims_specs_with_reads %>%
    filter(.data$is_valid) %>%
    dplyr::select(
      dplyr::all_of(c(
        "eco_state", "sim_number", "organism", "abs_abundance", "rel_abundance",
        "diversity", "diversity_level", "num_reads_per_organism",
        "sampling_depth", "run_accession", "available_reads"
      ))
    )

  # Report excluded simulations based on required reads vs available reads.
  excluded_sims <- sim_validity %>% filter(!.data$is_valid)
  if (nrow(excluded_sims) > 0) {
    cli::cli_alert_warning(
      "Excluded {nrow(excluded_sims)} simulations due to read limitations"
    )
  }

  sims_specs_valid
}

# ============================================================================
# DIVERSITY FILTERING
# ============================================================================

#' @title Select Simulations by Diversity
#' @description Selects n_sims_per_diversity_level simulations
#' from each diversity level (low, mid, high)
#' @param sims_specs_valid Valid simulation specifications
#' @param n_sims_per_diversity_level Number of simulations per diversity level
#' @return Data frame with selected simulations
select_sims_by_diversity <- function(
  sims_specs_valid,
  n_sims_per_diversity_level
) {
  sims_diversity <- sims_specs_valid %>%
    dplyr::select(
      dplyr::all_of(c(
        "eco_state", "sim_number", "diversity", "diversity_level",
        "sampling_depth"
      ))
    ) %>%
    dplyr::distinct()

  # Identify the maximum sampling depth available
  max_sampling_depth <- max(sims_diversity$sampling_depth)

  # Select simulations at the highest sampling depth first,
  # ensuring they satisfy the most demanding read requirements.
  sims_from_max_depth <- sims_diversity %>%
    dplyr::filter(.data$sampling_depth == max_sampling_depth) %>%
    dplyr::group_by(dplyr::across("diversity_level")) %>%
    dplyr::slice_min(
      order_by = dplyr::pick(dplyr::all_of(c("sim_number", "diversity"))),
      n = n_sims_per_diversity_level,
      with_ties = FALSE
    ) %>%
    dplyr::mutate(
      diversity_id = paste0(.data$diversity_level, "_", dplyr::row_number())
    ) %>%
    dplyr::ungroup()

  # Expand the selected simulations to include all sampling depths
  # using the same sim_num for each diversity_id across all depths
  sims_diversity_expanded <- sims_from_max_depth %>%
    dplyr::select(
      dplyr::all_of(
        c("eco_state", "sim_number", "diversity_level", "diversity_id")
      )
    ) %>%
    tidyr::crossing(
      sampling_depth = unique(sims_diversity$sampling_depth)
    )

  # Keep only the simulations matching the selected sim_number across depths.
  sims_specs_pick <- sims_specs_valid %>%
    dplyr::inner_join(
      sims_diversity_expanded,
      by = c(
        "eco_state",
        "sim_number",
        "diversity_level",
        "sampling_depth"
      )
    )

  # Report if some diversity levels lack enough valid simulations
  # at the highest sampling depth.
  insufficient_sims <- sims_from_max_depth %>%
    dplyr::group_by(dplyr::across("diversity_level")) %>%
    dplyr::summarize(
      n_valid = dplyr::n_distinct(.data$diversity_id),
      .groups = "drop"
    ) %>%
    dplyr::filter(.data$n_valid < n_sims_per_diversity_level)

  if (nrow(insufficient_sims) > 0) {
    cli::cli_alert_warning(
      paste0(
        "Insufficient valid simulations for some diversity levels ",
        "at highest depth"
      )
    )
  }

  sims_specs_pick
}

# ============================================================================
# COLOR UTILITIES
# ============================================================================

#' @title Create Colorblind-Friendly Organism Color Mapping
#' @description Creates a colorblind-friendly palette for organisms
#' using khroma's smooth rainbow palette with range c(0.25, 1)
#' @param organisms Vector of organism names
#' @return Named vector of colors keyed by organism
create_organism_color_mapping <- function(organisms) {
  unique_organisms <- sort(unique(organisms))
  palette_fn <- khroma::color("smooth rainbow")
  colors <- palette_fn(length(unique_organisms), range = c(0.25, 1))
  names(colors) <- unique_organisms
  colors
}

# ============================================================================
# OUTPUT GENERATION
# ============================================================================

#' @title Generate Individual Specification Plots
#' @description Creates individual bar plots for each simulation
#' showing relative abundance by organism
#' @param sims_specs Simulation specifications
#' @param output_dir Output directory
gen_individual_plots <- function(sims_specs, output_dir) {
  specs_dir <- file.path(output_dir, "plots", "specs")
  if (!dir.exists(specs_dir)) {
    dir.create(specs_dir, recursive = TRUE)
  }

  # Load SGB mapping for species labels
  mash_top_hits_file <- here("data", "mapping", "mash.tsv")
  if (!file.exists(mash_top_hits_file)) {
    cli::cli_abort(
      c(
        "!" = "SGB mapping file not found: {mash_top_hits_file}",
        "i" = "Run mash_top_hits_summary.R to generate this file."
      )
    )
  }

  sgb_mapping <- readr::read_tsv(
    mash_top_hits_file,
    show_col_types = FALSE
  ) %>%
    dplyr::select(
      dplyr::all_of(c("run_accession", "organism", "sgb_id"))
    )

  # Create consistent color mapping for all organisms
  organism_colors <- create_organism_color_mapping(sims_specs$organism)

  # Create species label lookup (same logic as gen_community_profile_plots)
  # Check if run_accession exists in the data
  has_run_accession <- "run_accession" %in% names(sims_specs)

  if (has_run_accession) {
    organism_sgb_map <- sims_specs %>%
      dplyr::select(
        dplyr::all_of(c("organism", "run_accession"))
      ) %>%
      dplyr::distinct() %>%
      dplyr::left_join(
        sgb_mapping,
        by = c("run_accession", "organism")
      )
  } else {
    # If run_accession is not available, join only on organism
    organism_sgb_map <- sims_specs %>%
      dplyr::select(
        dplyr::all_of("organism")
      ) %>%
      dplyr::distinct() %>%
      dplyr::left_join(
        sgb_mapping %>%
          dplyr::select(dplyr::all_of(c("organism", "sgb_id"))) %>%
          dplyr::distinct(),
        by = "organism"
      )
  }

  organism_sgb_map <- organism_sgb_map %>%
    dplyr::mutate(
      species_only = stringr::str_replace(
        .data$organism,
        "^([A-Za-z][A-Za-z-]+\\s+[a-z][a-z-]+).*",
        "\\1"
      ),
      formatted_label = dplyr::case_when(
        !is.na(.data$sgb_id) & .data$sgb_id != "NA" ~ paste0(
          "s__", .data$species_only, ".t__", .data$sgb_id
        ),
        TRUE ~ paste0("s__", .data$species_only)
      )
    ) %>%
    dplyr::select(
      dplyr::all_of(c("organism", "formatted_label"))
    )

  species_label_lookup <- organism_sgb_map %>%
    dplyr::group_by(dplyr::across("organism")) %>%
    dplyr::slice_head(n = 1) %>%
    dplyr::ungroup() %>%
    tibble::deframe()

  # Split data into groups for parallel processing
  plot_groups <- sims_specs %>%
    dplyr::group_by(
      dplyr::across(c("eco_state", "sim_number"))
    ) %>%
    dplyr::group_split()

  # Generate individual specification plots sequentially.
  # Each plot shows relative abundance by organism.
  # Using sequential processing
  # to avoid MultisessionFuture graphics device warnings
  purrr::walk(plot_groups, function(sim_data) {
    eco_state <- sim_data$eco_state[1]
    sim_num <- sim_data$sim_number[1]
    diversity_level <- sim_data$diversity_level[1]

    # Filter to one sampling depth
    # (relative abundance is the same across depths)
    # Use minimum depth to ensure we have data
    plot_data <- sim_data %>%
      dplyr::filter(.data$sampling_depth == min(.data$sampling_depth))

    plot <- ggplot2::ggplot(
      plot_data,
      ggplot2::aes(x = 1, y = .data$rel_abundance, fill = .data$organism)
    ) +
      ggplot2::geom_bar(
        stat = "identity",
        color = "black",
        linewidth = 0.1,
        width = 0.002
      ) +
      ggplot2::scale_fill_manual(
        values = organism_colors,
        breaks = names(species_label_lookup),
        labels = species_label_lookup,
        name = "Species"
      ) +
      ggplot2::scale_x_continuous(
        limits = c(0.998, 1.002),
        expand = ggplot2::expansion(mult = 0, add = 0.0005)
      ) +
      ggplot2::scale_y_continuous(
        expand = ggplot2::expansion(mult = c(0.05, 0.05))
      ) +
      ggplot2::theme_bw() +
      ggplot2::theme(
        axis.text.x = ggplot2::element_blank(),
        axis.ticks.x = ggplot2::element_blank(),
        axis.line.x = ggplot2::element_blank(),
        plot.title = ggplot2::element_text(hjust = 0.5),
        legend.text = ggplot2::element_text(face = "italic"),
        legend.title = ggplot2::element_text(face = "bold"),
        panel.grid = ggplot2::element_blank(),
        plot.margin = ggplot2::margin(10, 5, 10, 5)
      ) +
      ggplot2::labs(
        title = stringr::str_to_title(
          paste0(eco_state, " #", sim_num, " - ", diversity_level, " Diversity")
        ),
        x = NULL,
        y = "Relative Abundance"
      )

    legend <- ggpubr::get_legend(plot)
    plot_no_legend <- plot + ggplot2::theme(legend.position = "none")
    stacked_plot <- ggpubr::ggarrange(
      plot_no_legend,
      ggpubr::as_ggplot(legend),
      ncol = 2,
      widths = c(0.25, 0.75)
    )

    ggplot2::ggsave(
      file.path(
        specs_dir,
        paste0(
          stringr::str_to_lower(eco_state), "_",
          sprintf("%03d", sim_num), "_",
          diversity_level, "_diversity_specs.pdf"
        )
      ),
      plot = stacked_plot,
      device = "pdf",
      height = 20,
      width = 22,
      units = "cm"
    )
  })
}

#' @title Generate Community Profile Plots
#' @description Creates stacked bar plots showing absolute abundances
#' across sampling depths for each simulation number
#' @param sims_specs_pick Picked simulation specifications
#' @param output_dir Output directory
gen_community_profile_plots <- function(sims_specs_pick, output_dir) {
  communities_dir <- file.path(output_dir, "plots", "communities")
  if (!dir.exists(communities_dir)) {
    dir.create(communities_dir, recursive = TRUE)
  }

  mash_top_hits_file <- here("data", "mapping", "mash.tsv")
  if (!file.exists(mash_top_hits_file)) {
    cli::cli_abort(
      c(
        "!" = "SGB mapping file not found: {mash_top_hits_file}",
        "i" = "Run mash_top_hits_summary.R to generate this file."
      )
    )
  }

  sgb_mapping <- readr::read_tsv(
    mash_top_hits_file,
    show_col_types = FALSE
  ) %>%
    dplyr::select(
      dplyr::all_of(c("run_accession", "organism", "sgb_id"))
    )

  sims_specs_pick <- sims_specs_pick %>%
    dplyr::mutate(
      sim_number_final = as.integer(
        stringr::str_extract(.data$diversity_id, "[0-9]+$")
      )
    )

  organism_colors <- create_organism_color_mapping(sims_specs_pick$organism)

  organism_sgb_map <- sims_specs_pick %>%
    dplyr::select(
      dplyr::all_of(c("organism", "run_accession"))
    ) %>%
    dplyr::distinct() %>%
    dplyr::left_join(
      sgb_mapping,
      by = c("run_accession", "organism")
    ) %>%
    dplyr::mutate(
      species_only = stringr::str_replace(
        .data$organism,
        "^([A-Za-z][A-Za-z-]+\\s+[a-z][a-z-]+).*",
        "\\1"
      ),
      formatted_label = dplyr::case_when(
        !is.na(.data$sgb_id) & .data$sgb_id != "NA" ~ paste0(
          "s__", .data$species_only, ".t__", .data$sgb_id
        ),
        TRUE ~ paste0("s__", .data$species_only)
      )
    ) %>%
    dplyr::select(
      dplyr::all_of(c("organism", "formatted_label"))
    )

  species_label_lookup <- organism_sgb_map %>%
    dplyr::group_by(dplyr::across("organism")) %>%
    dplyr::slice_head(n = 1) %>%
    dplyr::ungroup() %>%
    tibble::deframe()

  unique_sim_numbers <- sort(unique(sims_specs_pick$sim_number_final))
  purrr::walk(unique_sim_numbers, function(sim_num_final) {
    sim_data <- sims_specs_pick %>%
      dplyr::filter(.data$sim_number_final == sim_num_final) %>%
      dplyr::mutate(
        sampling_depth_label = dplyr::case_when(
          .data$sampling_depth == 1e4 ~ "10K",
          .data$sampling_depth == 1e5 ~ "100K",
          .data$sampling_depth == 1e6 ~ "1M",
          .data$sampling_depth == 1e7 ~ "10M",
          TRUE ~ format(.data$sampling_depth, scientific = TRUE)
        ),
        sampling_depth_label = factor(
          .data$sampling_depth_label,
          levels = c("10K", "100K", "1M", "10M")
        ),
        diversity_level_label = dplyr::case_when(
          .data$diversity_level == "low" ~ "Low diversity",
          .data$diversity_level == "mid" ~ "Moderate diversity",
          TRUE ~ "High diversity"
        ),
        diversity_level_label = factor(
          .data$diversity_level_label,
          levels = c("Low diversity", "Moderate diversity", "High diversity")
        )
      )

    max_reads <- max(sim_data$num_reads_per_organism, na.rm = TRUE)
    if (!is.finite(max_reads) || max_reads == 0) {
      max_reads <- 1
    }

    plot <- ggplot2::ggplot(
      sim_data,
      ggplot2::aes(
        x = .data$sampling_depth_label,
        y = .data$num_reads_per_organism
      )
    ) +
      ggplot2::geom_bar(
        ggplot2::aes(fill = .data$organism),
        stat = "identity",
        color = "black",
        linewidth = 0.1
      ) +
      ggplot2::facet_wrap(~diversity_level_label, ncol = 3) +
      ggplot2::scale_y_continuous(
        labels = scales::label_number(scale = 1e-6, suffix = "M"),
        expand = ggplot2::expansion(mult = c(0, 0))
      ) +
      ggplot2::scale_fill_manual(
        values = organism_colors,
        breaks = names(species_label_lookup),
        labels = species_label_lookup,
        name = "Species"
      ) +
      ggplot2::coord_cartesian(
        ylim = c(-0.1 * max_reads, max_reads * 1.05)
      ) +
      ggplot2::theme_bw() +
      ggplot2::theme(
        axis.title = ggplot2::element_text(face = "bold"),
        legend.text = ggplot2::element_text(face = "italic"),
        legend.title = ggplot2::element_text(face = "bold"),
        plot.title = ggplot2::element_text(hjust = 0.5),
        strip.text = ggplot2::element_text(face = "bold"),
        strip.background = ggplot2::element_rect(fill = "white"),
        panel.grid = ggplot2::element_blank(),
        plot.margin = ggplot2::margin(20, 20, 20, 20)
      ) +
      ggplot2::labs(
        title = paste(
          "Simulation", sim_num_final,
          "- Microbial Community Profiles"
        ),
        x = "Sampling depth (reads)",
        y = "Absolute abundance (reads)"
      ) +
      ggplot2::annotate(
        "segment",
        x = 0.8, xend = 4.2,
        y = -0.05 * max_reads,
        yend = -0.05 * max_reads,
        arrow = ggplot2::arrow(
          length = grid::unit(0.1, "inches"),
          ends = "both"
        ),
        color = "black",
        linewidth = 0.6
      ) +
      ggplot2::annotate(
        "text",
        x = 0.8,
        y = -0.08 * max_reads,
        label = "Biopsy",
        hjust = 0,
        vjust = 0.5,
        fontface = "bold",
        size = 3.5
      ) +
      ggplot2::annotate(
        "text",
        x = 4.2,
        y = -0.08 * max_reads,
        label = "Fecal",
        hjust = 1,
        vjust = 0.5,
        fontface = "bold",
        size = 3.5
      )

    ggplot2::ggsave(
      file.path(
        communities_dir,
        sprintf("sim_%03d_community_profiles.pdf", sim_num_final)
      ),
      plot = plot,
      device = "pdf",
      height = 20,
      width = 30,
      units = "cm"
    )
  })
}

#' @title Generate Diversity Plot
#' @description Creates a plot showing diversity values for all simulations
#' @param sims_specs Simulation specifications
#' @param output_dir Output directory
gen_diversity_plot <- function(sims_specs, output_dir) {
  summary_dir <- file.path(output_dir, "plots", "summary")
  if (!dir.exists(summary_dir)) {
    dir.create(summary_dir, recursive = TRUE)
  }

  # Create diversity plot data using already-calculated diversity levels
  plot_diversity <- sims_specs %>%
    dplyr::select(
      dplyr::all_of(
        c(
          "eco_state",
          "sim_number",
          "diversity",
          "diversity_level",
          "diversity_id"
        )
      )
    ) %>%
    dplyr::distinct() %>%
    dplyr::mutate(
      eco_id = paste(.data$eco_state, .data$sim_number, sep = "_")
    ) %>%
    dplyr::arrange(
      factor(.data$diversity_level, levels = c("low", "mid", "high")),
      readr::parse_number(.data$diversity_id)
    )

  # Order samples for plotting
  plot_diversity$diversity_id <- factor(
    plot_diversity$diversity_id,
    levels = plot_diversity$diversity_id
  )

  # Create a diversity plot showing diversity values for all simulations.
  plot <- ggplot2::ggplot(
    plot_diversity,
    ggplot2::aes(
      x = .data$diversity_id,
      y = .data$diversity,
      fill = .data$diversity_level
    )
  ) +
    ggplot2::geom_bar(stat = "identity") +
    ggplot2::scale_fill_manual(
      values = c("low" = "red", "mid" = "yellow", "high" = "green"),
      labels = c("low" = "Low", "mid" = "Moderate", "high" = "High"),
      name = "Diversity level"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 0, hjust = 0.5, vjust = 0.5),
      plot.title = ggplot2::element_text(hjust = 0.5)
    ) +
    ggplot2::labs(
      title = "Diversity Distribution across all Simulations",
      x = "Simulations",
      y = "Simpson's Diversity Index"
    ) +
    ggplot2::coord_cartesian(ylim = c(0, 1)) +
    ggplot2::geom_hline(yintercept = c(0.5, 0.75))

  ggplot2::ggsave(
    file.path(summary_dir, "sims_diversity_distribution.pdf"),
    plot = plot,
    device = "pdf",
    height = 15,
    width = 30,
    units = "cm"
  )
}

#' @title Generate Summary Plot
#' @description Creates a comprehensive bar plot
#' showing picked simulations specifications with relative abundances
#' @param sims_specs_pick Picked simulation specifications
#' @param output_dir Output directory
gen_summary_plot <- function(sims_specs_pick, output_dir) {
  summary_dir <- file.path(output_dir, "plots", "summary")
  if (!dir.exists(summary_dir)) {
    dir.create(summary_dir, recursive = TRUE)
  }

  mash_top_hits_file <- here("data", "mapping", "mash.tsv")
  if (!file.exists(mash_top_hits_file)) {
    cli::cli_abort(
      c(
        "!" = "SGB mapping file not found: {mash_top_hits_file}",
        "i" = "Run mash_top_hits_summary.R to generate this file."
      )
    )
  }

  sgb_mapping <- readr::read_tsv(
    mash_top_hits_file,
    show_col_types = FALSE
  ) %>%
    dplyr::select(
      dplyr::all_of(c("run_accession", "organism", "sgb_id"))
    )

  organism_colors <- create_organism_color_mapping(sims_specs_pick$organism)

  organism_sgb_map <- sims_specs_pick %>%
    dplyr::select(
      dplyr::all_of(c("organism", "run_accession"))
    ) %>%
    dplyr::distinct() %>%
    dplyr::left_join(
      sgb_mapping,
      by = c("run_accession", "organism")
    ) %>%
    dplyr::mutate(
      species_only = stringr::str_replace(
        .data$organism,
        "^([A-Za-z][A-Za-z-]+\\s+[a-z][a-z-]+).*",
        "\\1"
      ),
      formatted_label = dplyr::case_when(
        !is.na(.data$sgb_id) & .data$sgb_id != "NA" ~ paste0(
          "s__", .data$species_only, ".t__", .data$sgb_id
        ),
        TRUE ~ paste0("s__", .data$species_only)
      )
    ) %>%
    dplyr::select(
      dplyr::all_of(c("organism", "formatted_label"))
    )

  species_label_lookup <- organism_sgb_map %>%
    dplyr::group_by(dplyr::across("organism")) %>%
    dplyr::slice_head(n = 1) %>%
    dplyr::ungroup() %>%
    tibble::deframe()

  plot <- sims_specs_pick %>%
    dplyr::group_by(dplyr::across("diversity_id")) %>%
    dplyr::mutate(diversity_id = factor(.data$diversity_id, levels = c(
      "low_1", "low_2", "low_3", "low_4", "low_5",
      "mid_1", "mid_2", "mid_3", "mid_4", "mid_5",
      "high_1", "high_2", "high_3", "high_4", "high_5"
    ))) %>%
    ggpubr::ggbarplot(
      x = "diversity_id", y = "rel_abundance", fill = "organism"
    ) +
    ggplot2::scale_fill_manual(
      values = organism_colors,
      breaks = names(species_label_lookup),
      labels = species_label_lookup,
      name = "Species"
    ) +
    ggplot2::theme_bw() +
    ggplot2::theme(
      axis.title = ggplot2::element_text(face = "bold"),
      legend.text = ggplot2::element_text(face = "italic"),
      legend.title = ggplot2::element_text(face = "bold"),
      plot.title = ggplot2::element_text(hjust = 0.5)
    ) +
    ggplot2::labs(
      title = "Picked Simulations: Relative Abundance by Organism",
      x = "Simulation", y = "Relative abundance", fill = "Organism"
    )

  ggplot2::ggsave(
    file.path(summary_dir, "sims_picked_specs.pdf"),
    plot = plot,
    device = "pdf",
    height = 15,
    width = 35,
    units = "cm"
  )
}

#' @title Write Simulations Specifications
#' @description Writes picked simulation specifications to a TSV file
#' @param sims_specs_pick Picked simulation specifications
#' @param output_dir Output directory
write_sim_specs <- function(sims_specs_pick, output_dir) {
  readr::write_tsv(
    sims_specs_pick,
    file.path(output_dir, "sims_specs.tsv")
  )
}

#' @title Generate Subsampling Specifications
#' @description Creates subsampling specifications and parameters (rnd_seed)
#' for later use with SeqKit
#' @param sims_specs_pick Picked simulation specifications
#' @param sampling_depths Vector of sampling depths
#' @param output_dir Output directory
gen_subsampling_comms <- function(
  sims_specs_pick,
  sampling_depths,
  output_dir
) {
  seqkit_subsampling_specs <- purrr::map_dfr(
    sampling_depths, function(sampling_depth) {
      sims_specs_to_subsample <- sims_specs_pick %>%
        # Use the unquote operator (!!) to distinguish between column name
        # and loop variable
        # Without !!: filter(sampling_depth == sampling_depth) compares column
        # to itself
        # With !!: filter(sampling_depth == !!sampling_depth) compares column
        # to variable value
        filter(
          (.data$sampling_depth == !!sampling_depth) &
            (.data$num_reads_per_organism > 0)
        )

      # Generate SeqKit subsampling specifications for each simulation.
      sims_specs_to_subsample %>%
        dplyr::mutate(
          rnd_seed = sample(RND_SEED_RANGE, size = dplyr::n(), replace = TRUE),
          forward_subsampling_spec = paste0(
            .data$run_accession, "_1.fastq.gz ",
            .data$rnd_seed, " ", .data$num_reads_per_organism, " ",
            .data$diversity_level, "_diversity/individual/",
            .data$run_accession, "_", .data$diversity_id, "_",
            .data$sampling_depth, "_1.fastq.gz"
          ),
          reverse_subsampling_spec = paste0(
            .data$run_accession, "_2.fastq.gz ",
            .data$rnd_seed, " ", .data$num_reads_per_organism, " ",
            .data$diversity_level, "_diversity/individual/",
            .data$run_accession, "_", .data$diversity_id, "_",
            .data$sampling_depth, "_2.fastq.gz"
          ),
          sampling_depth = !!sampling_depth
        ) %>%
        dplyr::select(
          dplyr::all_of(c(
            "forward_subsampling_spec",
            "reverse_subsampling_spec",
            "sampling_depth",
            "diversity_id"
          ))
        )
    },
    .id = NULL
  )

  # Write a SeqKit subsampling specifications file per sampling depth.
  seqkit_subsampling_specs %>%
    dplyr::group_by(dplyr::across("sampling_depth")) %>%
    dplyr::group_walk(function(data, group) {
      sampling_depth <- group$sampling_depth

      subsampling_specs <- data %>%
        dplyr::select(
          dplyr::all_of(
            c("forward_subsampling_spec", "reverse_subsampling_spec")
          )
        ) %>%
        # Use pivot_longer to convert the data frame from wide to long format.
        # This is necessary because the data frame is currently in wide format,
        # with each command in a separate column.
        # We need one subsampling specification for SeqKit per line.
        # Note that pivot_longer() is an updated approach to gather(),
        # designed to be both simpler to use and to handle more use cases.
        tidyr::pivot_longer(
          cols = c("forward_subsampling_spec", "reverse_subsampling_spec"),
          names_to = "read_type",
          values_to = "command"
        ) %>%
        dplyr::pull(.data$command) %>%
        as.character()

      writeLines(
        subsampling_specs,
        con = file.path(
          output_dir,
          paste0(
            "seqkit_subsampling_specs_",
            format(sampling_depth, scientific = TRUE),
            ".txt"
          )
        )
      )
    })
}

#' @title Count Valid Simulations Per Combination
#' @description Counts valid simulations per (sampling_depth, diversity_level)
#'   combination
#' @param sims_specs_valid Valid simulation specifications
#' @param sims_specs_with_reads Simulation specifications with read counts
#' @return Data frame with counts per combination
count_valid_sims_per_combo <- function(
  sims_specs_valid,
  sims_specs_with_reads
) {
  sims_specs_valid %>%
    dplyr::distinct(
      dplyr::across(
        c("eco_state", "sim_number", "sampling_depth")
      )
    ) %>%
    dplyr::left_join(
      sims_specs_with_reads %>%
        dplyr::select(
          dplyr::all_of(c(
            "eco_state", "sim_number", "sampling_depth", "diversity_level"
          ))
        ) %>%
        dplyr::distinct(),
      by = c("eco_state", "sim_number", "sampling_depth")
    ) %>%
    dplyr::count(
      dplyr::across(c("sampling_depth", "diversity_level")),
      name = "n_valid_sims", sort = TRUE
    ) %>%
    dplyr::mutate(
      diversity_level = factor(
        .data$diversity_level,
        levels = c("low", "mid", "high")
      )
    ) %>%
    dplyr::arrange(dplyr::across(c("sampling_depth", "diversity_level")))
}

#' @title Calculate Summary Statistics
#' @description Calculates all summary statistics from simulation data
#' @param simulation_data List containing all simulation data
#' @param config Configuration parameters
#' @return List containing all calculated statistics
calc_summary_stats <- function(simulation_data, config) {
  # Extract simulation data
  sims_specs_with_reads <- simulation_data$sims_specs_with_reads
  sims_specs_valid <- simulation_data$sims_specs_valid
  sims_specs_pick <- simulation_data$sims_specs_pick
  run_organism_map <- simulation_data$run_organism_map

  # Calculate statistics
  n_organisms_per_sim <- nrow(run_organism_map)
  total_sims_generated <- nrow(sims_specs_with_reads) / n_organisms_per_sim

  valid_sims_per_combination <- count_valid_sims_per_combo(
    sims_specs_valid,
    sims_specs_with_reads
  )

  total_valid_sims <- sum(valid_sims_per_combination$n_valid_sims)
  total_excluded_sims <- total_sims_generated - total_valid_sims
  total_picked_sims <- sims_specs_pick %>%
    dplyr::distinct(
      dplyr::across(
        c("eco_state", "sim_number", "sampling_depth")
      )
    ) %>%
    nrow()

  n_sampling_depths <- length(config$sampling_depths)
  n_output_files <- n_sampling_depths + 1

  list(
    total_sims_generated = total_sims_generated,
    total_valid_sims = total_valid_sims,
    total_excluded_sims = total_excluded_sims,
    total_picked_sims = total_picked_sims,
    valid_sims_per_combination = valid_sims_per_combination,
    n_output_files = n_output_files
  )
}

#' @title Log Valid Simulations Breakdown
#' @description Logs breakdown of valid simulations
#' by sampling depth and diversity level
#' @param valid_sims_per_combination Data frame with valid simulations
#' per combination
#' @return NULL (invisibly)
log_valid_sims_breakdown <- function(valid_sims_per_combination) {
  cli::cli_alert_info(
    "  Valid simulations by (sampling_depth, diversity_level):"
  )
  for (i in seq_len(nrow(valid_sims_per_combination))) {
    depth <- valid_sims_per_combination$sampling_depth[i]
    level <- as.character(valid_sims_per_combination$diversity_level[i])
    count <- valid_sims_per_combination$n_valid_sims[i]
    cli::cli_alert_info(sprintf(
      "    Depth %s - %s diversity: %s simulations",
      depth, level, count
    ))
  }

  invisible(NULL)
}

#' @title Log Summary Statistics
#' @description Logs results summary for the synthetic dataset generation
#' @param simulation_data List containing all simulation data
#' @param config Configuration parameters
#' @return NULL (invisibly)
log_summary_stats <- function(simulation_data, config) {
  stats <- calc_summary_stats(simulation_data, config)

  cli::cli_h2("Results Summary")
  cli::cli_alert_info(
    "  Simulations generated: {stats$total_sims_generated}"
  )
  cli::cli_alert_info(
    "  Valid simulations (after filtering): {stats$total_valid_sims}"
  )
  cli::cli_alert_info(
    "  Excluded simulations: {stats$total_excluded_sims}"
  )
  cli::cli_alert_info(
    "  Picked simulations: {stats$total_picked_sims}"
  )

  log_valid_sims_breakdown(stats$valid_sims_per_combination)

  cli::cli_alert_info("  Output files generated: {stats$n_output_files}")
  if (!config$no_plots) {
    cli::cli_alert_info("    (including visualization plots)")
  } else {
    cli::cli_alert_info("    (plots disabled)")
  }
  cli::cli_alert_info("Output files saved in: {config$output_dir}")

  invisible(NULL)
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

#' Main function to run the synthetic dataset generation pipeline
#' @title Main Pipeline Execution
#' @description Orchestrates the complete pipeline with CLI progress reporting
#' @return NULL (invisibly)
main <- function() {
  cli::cli_h1("Synthetic Dataset Generator")
  cli::cli_alert_info("Script started at: {format(Sys.time())}")

  opt <- parse_cli_arguments()
  config <- initialize_configuration(opt)

  cli::cli_h2("Configuration:")
  cli::cli_alert_info(
    "- Simulations per ecology state: {config$n_sims_per_ecology_state}"
  )
  cli::cli_alert_info(
    "- Simulations per diversity level: {config$n_sims_per_diversity_level}"
  )
  cli::cli_alert_info("- Output directory: {config$output_dir}")

  cli::cli_h2("Execution:")

  # Phase 1: Data Loading
  cli::cli_alert_info("(1/6) Started loading data.")
  cli::cli_progress_step(
    msg = "(1/6) Loading data...",
    msg_done = "(1/6) Loaded data.",
    msg_failed = "(1/6) Failed to load data.",
    spinner = TRUE
  )
  run_organism_map <- load_organism_mapping(config)
  available_reads <- load_available_reads(config, run_organism_map)
  cli::cli_progress_done()

  # Phase 2: Simulations Generation
  cli::cli_alert_info("(2/6) Started generating simulation specifications.")
  cli::cli_progress_step(
    msg = "(2/6) Generating simulation specifications...",
    msg_done = "(2/6) Generated simulation specifications.",
    msg_failed = "(2/6) Failed to generate simulation specifications.",
    spinner = TRUE
  )
  sims_specs <- gen_sim_specs(config, run_organism_map)
  cli::cli_progress_done()

  # Phase 3: Read Count Generation
  cli::cli_alert_info("(3/6) Started generating read counts.")
  cli::cli_progress_step(
    msg = "(3/6) Generating read counts...",
    msg_done = "(3/6) Generated read counts.",
    msg_failed = "(3/6) Failed to generate read counts.",
    spinner = TRUE
  )
  sims_specs_with_reads <- gen_read_counts(
    sims_specs,
    config$sampling_depths
  )
  cli::cli_progress_done()

  # Phase 4: Validity Filtering
  cli::cli_alert_info("(4/6) Started filtering valid simulations.")
  cli::cli_progress_step(
    msg = "(4/6) Filtering valid simulations...",
    msg_done = "(4/6) Filtered valid simulations.",
    msg_failed = "(4/6) Failed to filter valid simulations.",
    spinner = TRUE
  )
  sims_specs_valid <- filter_valid_sims(
    sims_specs_with_reads,
    run_organism_map,
    available_reads
  )
  cli::cli_progress_done()

  # Phase 5: Diversity Selection
  cli::cli_alert_info(
    "(5/6) Started selecting simulations by diversity levels."
  )
  cli::cli_progress_step(
    msg = "(5/6) Selecting simulations by diversity levels...",
    msg_done = "(5/6) Selected simulations by diversity levels.",
    msg_failed = "(5/6) Failed to select simulations by diversity levels.",
    spinner = TRUE
  )
  sims_specs_pick <- select_sims_by_diversity(
    sims_specs_valid,
    config$n_sims_per_diversity_level
  )
  cli::cli_progress_done()

  # Phase 6: Output Generation
  cli::cli_alert_info("(6/6) Started generating output files.")
  cli::cli_progress_step(
    msg = "(6/6) Generating output files...",
    msg_done = "(6/6) Generated output files.",
    msg_failed = "(6/6) Failed to generate output files.",
    spinner = TRUE
  )
  if (!config$no_plots) {
    gen_individual_plots(sims_specs_pick, config$output_dir)
    gen_diversity_plot(sims_specs_pick, config$output_dir)
    gen_summary_plot(sims_specs_pick, config$output_dir)
    gen_community_profile_plots(sims_specs_pick, config$output_dir)
  }
  write_sim_specs(sims_specs_pick, config$output_dir)
  gen_subsampling_comms(
    sims_specs_pick,
    config$sampling_depths,
    config$output_dir
  )
  cli::cli_progress_done()

  simulation_data <- list(
    sims_specs_with_reads = sims_specs_with_reads,
    sims_specs_valid = sims_specs_valid,
    sims_specs_pick = sims_specs_pick,
    run_organism_map = run_organism_map
  )
  log_summary_stats(simulation_data, config)

  cli::cli_alert_success("Synthetic dataset generation complete.")

  invisible(NULL)
}

# Run main function if script is executed directly
if (!interactive()) {
  main()
}
