#!/usr/bin/env Rscript

#' @title Mash Screen Top Hits Summary
#' @author Verónica Llorens Rico
#' @author Francisco Merino-Casallo
#' @date 2025-01-27
#' @description Summarizes Mash screen top hits per run and
#'   maps SGB to species taxonomy
#'
#' @details Processes Mash screen results to extract the highest identity match
#'   for each run accession, extracts SGB identifiers, and maps them to species
#'   taxonomy using the vOct22 CHOCOPhlAn database.
#'   Outputs a TSV with columns:
#'   \itemize{
#'     \item run_accession
#'     \item organism
#'     \item identity
#'     \item shared_hashes
#'     \item sgb_id
#'     \item taxonomy
#'   }
#'
#' @usage Rscript build_mash_mapping.R


# ============================================================================
# SETUP AND DEPENDENCIES
# ============================================================================

suppressPackageStartupMessages({
  library(here)
  library(cli)
  library(optparse)
})

# Functions from lib/R/verbosity.R are sourced at runtime,
#   so lintr cannot detect them statically.
# We suppress object_usage_linter warnings on specific lines
#   where these functions are called.
source(here("lib", "R", "verbosity.R"))

option_list <- list(
  optparse::make_option(
    c("-q", "--quiet"),
    action = "store_true",
    default = FALSE,
    help = "Suppress CLI progress output"
  )
)

opt_parser <- optparse::OptionParser(option_list = option_list)
opt <- optparse::parse_args(opt_parser)

if (isTRUE(opt$quiet)) {
  smg_set_verbosity("quiet")
}


RUNS_CSV <- here(
  "data", "mapping", "run_organism_map.csv"
)
SCREENS_DIR <- here(
  "data", "mapping", "mash_screening"
)
MPA_SPECIES <- here(
  "data", "mapping", "mpa_vOct22_CHOCOPhlAnSGB_202403_species.txt"
)
OUT_PATH <- here(
  "data", "mapping", "mash.tsv"
)


# Helpers
trim_ws <- function(x) sub("^[[:space:]]+|[[:space:]]+$", "", x)

extract_sgb_from_fields <- function(path_field, comment_field) {
  if (!is.na(comment_field) && nzchar(comment_field)) {
    cf <- sub("^\\[[^]]+\\][[:space:]]*", "", comment_field)
    first_tok <- strsplit(cf, "\\|")[[1]][1]
    first_tok <- trim_ws(first_tok)
    if (!is.na(first_tok) && grepl("^SGB[0-9]+$", first_tok)) {
      first_tok
    }
  }

  if (!is.na(path_field) && nzchar(path_field)) {
    base <- basename(path_field)
    base <- sub("_pangenome[0-9]+\\.fna\\.gz$", "", base)
    base <- sub("\\.fna\\.gz$", "", base)
    m <- regmatches(base, regexpr("SGB[0-9]+", base))

    if (length(m) == 1 && nzchar(m)) {
      m
    } else {
      NA_character_
    }
  } else {
    NA_character_
  }
}

last_rank_from_taxonomy <- function(taxonomy_str) {
  if (is.na(taxonomy_str) || !nzchar(taxonomy_str)) {
    return(character(0))
  }
  taxa <- strsplit(taxonomy_str, ",")[[1]]
  taxa <- trim_ws(taxa)
  out <- character(0)
  for (tx in taxa) {
    ranks <- strsplit(tx, "\\|")[[1]]
    ranks <- ranks[nzchar(ranks)]
    if (length(ranks) == 0) next
    out <- c(out, ranks[length(ranks)])
  }

  unique(out)
}

format_last_rank <- function(rank_str) {
  if (is.na(rank_str) || !nzchar(rank_str)) {
    return("NA")
  }
  rank <- substr(rank_str, 1, 1)
  name <- sub("^[a-z]__", "", rank_str)
  name <- gsub("_", " ", name)
  label <- switch(rank,
    s = "species",
    g = "genus",
    f = "family",
    o = "order",
    c = "class",
    p = "phylum",
    k = "kingdom",
    "taxon"
  )
  paste0(name, " (", label, ")")
}

read_ground_truth <- function() {
  smg_cli_info("Loading ground truth: {.file {RUNS_CSV}}") # nolint: object_usage_linter
  df <- read.csv(RUNS_CSV, stringsAsFactors = FALSE)
  colnames(df) <- tolower(colnames(df))
  if (!all(c("run_accession", "organism") %in% colnames(df))) {
    cli_abort(c(
      "runs_csv must have columns: run_accession, organism",
      "x" = "Columns found: {paste(colnames(df), collapse = ', ')}"
    ))
  } else {
    df
  }
}

read_mpa_mapping <- function() {
  smg_cli_info("Loading SGB->taxonomy mapping: {.file {MPA_SPECIES}}") # nolint: object_usage_linter
  mpa_df <- utils::read.delim(
    MPA_SPECIES,
    header = FALSE, sep = "\t", quote = ""
  )
  colnames(mpa_df) <- c("sgb", "taxonomy")
  setNames(mpa_df$taxonomy, mpa_df$sgb)
}

list_screen_files <- function() {
  files <- list.files(SCREENS_DIR, pattern = "\\.tab$", full.names = TRUE)
  if (length(files) == 0) {
    cli_abort(c(
      "No .tab screen files found in {.file {SCREENS_DIR}}.",
      "x" = "Ensure files end with {.code _screen.tab} and are non-empty."
    ))
  } else {
    files
  }
}

parse_screen_top_hit <- function(fn) {
  run_id <- sub("_screen\\.tab$", "", basename(fn))
  df <- tryCatch(
    utils::read.delim(
      fn,
      header = FALSE, quote = "", fill = TRUE
    ),
    error = function(e) NULL
  )

  if (is.null(df) || nrow(df) == 0) {
    return(NULL)
  }

  suppressWarnings(id_num <- as.numeric(df[[1]]))

  id_num[is.na(id_num)] <- -Inf
  best_idx <- which.max(id_num)
  identity <- df[[1]][best_idx]

  if (ncol(df) >= 2) {
    shared <- df[[2]][best_idx]
  } else {
    shared <- NA_character_
  }

  comment_field <- NA_character_
  path_field <- NA_character_

  if (ncol(df) >= 7) {
    comment_field <- df[[7]][best_idx]
    path_field <- df[[6]][best_idx]
  } else if (ncol(df) == 6) {
    comment_field <- df[[6]][best_idx]
    path_field <- df[[5]][best_idx]
  } else if (ncol(df) >= 5) {
    comment_field <- df[[ncol(df)]][best_idx]
    path_field <- df[[ncol(df) - 1]][best_idx]
  }

  list(
    run_accession = run_id,
    identity = as.character(identity),
    shared_hashes = as.character(shared),
    path = path_field,
    comment = comment_field
  )
}

build_summary <- function(runs_df, sgb_to_tax) {
  smg_cli_info("Parsing Mash screen files: {.file {SCREENS_DIR}}") # nolint: object_usage_linter
  files <- list_screen_files()
  recs <- lapply(files, parse_screen_top_hit)
  recs <- recs[!vapply(recs, is.null, logical(1))]

  if (length(recs) == 0) {
    cli_abort(c(
      "Failed to parse Mash screen results.",
      "x" = "No valid summaries found in {.file {SCREENS_DIR}}.",
      "i" = "Ensure files end with {.code _screen.tab} and are non-empty."
    ))
  } else {
    out <- lapply(recs, function(r) {
      sgb <- extract_sgb_from_fields(r$path, r$comment)

      if (
        !is.na(sgb) &&
          !is.null(sgb_to_tax) &&
          (length(sgb_to_tax) > 0) &&
          !is.null(sgb_to_tax[[sgb]])
      ) {
        taxonomy_raw <- sgb_to_tax[[sgb]]
      } else {
        taxonomy_raw <- NA_character_
      }

      last_ranks <- last_rank_from_taxonomy(taxonomy_raw)
      if (length(last_ranks) == 0) {
        taxonomy_fmt <- "NA"
      } else {
        taxonomy_fmt <- paste(
          vapply(last_ranks, format_last_rank, ""),
          collapse = "; "
        )
      }

      data.frame(
        run_accession = r$run_accession,
        identity = r$identity,
        shared_hashes = r$shared_hashes,
        sgb_id = ifelse(is.na(sgb), "NA", sgb),
        taxonomy = taxonomy_fmt,
        stringsAsFactors = FALSE
      )
    })

    summary_df <- do.call(rbind, out)

    merge(
      runs_df[, c("run_accession", "organism")],
      summary_df,
      by = "run_accession",
      all.y = TRUE
    )
  }
}

write_tsv <- function(df, path) {
  smg_cli_info("Writing summary TSV: {.file {path}}") # nolint: object_usage_linter
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  con <- file(path, open = "wt")
  on.exit(close(con))
  writeLines(paste(colnames(df), collapse = "\t"), con)
  apply(df, 1, function(row) writeLines(paste(row, collapse = "\t"), con))
}

validate_required_files <- function() {
  if (!file.exists(RUNS_CSV)) {
    cli_abort(c(
      "Ground truth file missing",
      "x" = "Expected: {.file {RUNS_CSV}}",
      "i" = paste(
        "This file should be tracked in git.",
        "Try: git status or git pull to restore missing files.",
        sep = "\n"
      )
    ))
  } else if (!dir.exists(SCREENS_DIR)) {
    cli_abort(c(
      "Mash screen results directory missing",
      "x" = "Expected: {.file {SCREENS_DIR}}",
      "i" = "Run Mash screen analysis first"
    ))
  } else if (!file.exists(MPA_SPECIES)) {
    cli_abort(c(
      "SGB taxonomy mapping file missing",
      "x" = "Expected: {.file {MPA_SPECIES}}",
      "i" = paste(
        "Ensure the vOct22 mapping file is available",
        "This file should be tracked in git.",
        "Try: git status or git pull to restore missing files.",
        "Alternatively, download it from:",
        "http://cmprod1.cibio.unitn.it/biobakery4/metaphlan_databases/",
        "and place it in the data/mapping directory.",
        sep = "\n"
      )
    ))
  }
}

main <- function() {
  smg_cli_h1("Mash top hits summary") # nolint: object_usage_linter
  smg_cli_info("Project root: {.file {here()}}") # nolint: object_usage_linter

  validate_required_files()

  runs_df <- read_ground_truth()
  sgb_to_tax <- read_mpa_mapping()
  final_df <- build_summary(runs_df, sgb_to_tax)
  final_df <- final_df[
    ,
    c(
      "run_accession",
      "organism",
      "identity",
      "shared_hashes",
      "sgb_id",
      "taxonomy"
    )
  ]
  write_tsv(final_df, OUT_PATH)
  smg_cli_success("Wrote summary to {.file {OUT_PATH}}") # nolint: object_usage_linter
}

if (!interactive()) {
  main()
}
