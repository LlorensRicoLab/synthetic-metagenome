SMG_VERBOSITY_LEVELS <- c(quiet = 0, inform = 1, debug = 2)
SMG_DEFAULT_VERBOSITY <- "inform"

smg_normalize_verbosity <- function(level) {
  level <- tolower(level)
  if (!level %in% names(SMG_VERBOSITY_LEVELS)) {
    warning(
      sprintf(
        "Unknown verbosity level '%s'. Falling back to '%s'.",
        level,
        SMG_DEFAULT_VERBOSITY
      ),
      call. = FALSE
    )
    level <- SMG_DEFAULT_VERBOSITY
  }
  level
}

smg_init_verbosity <- function() {
  current <- getOption("smg.verbosity", NA_character_)
  if (is.na(current)) {
    env_val <- Sys.getenv("SMG_VERBOSITY", "")
    if (nzchar(env_val)) {
      current <- smg_normalize_verbosity(env_val)
    } else {
      current <- SMG_DEFAULT_VERBOSITY
    }
    options(smg.verbosity = current)
  }
  current
}

smg_set_verbosity <- function(level) {
  options(smg.verbosity = smg_normalize_verbosity(level))
}

smg_current_verbosity <- function() {
  smg_init_verbosity()
  getOption("smg.verbosity", SMG_DEFAULT_VERBOSITY)
}

smg_should_emit <- function(required = "inform") {
  required <- smg_normalize_verbosity(required)
  SMG_VERBOSITY_LEVELS[smg_current_verbosity()] >=
    SMG_VERBOSITY_LEVELS[required]
}

smg_cli_h1 <- function(...) {
  if (smg_should_emit("inform")) cli::cli_h1(..., .envir = parent.frame())
}

smg_cli_h2 <- function(...) {
  if (smg_should_emit("inform")) cli::cli_h2(..., .envir = parent.frame())
}

smg_cli_info <- function(...) {
  if (smg_should_emit("inform")) {
    cli::cli_alert_info(..., .envir = parent.frame())
  }
}

smg_cli_success <- function(...) {
  if (smg_should_emit("inform")) {
    cli::cli_alert_success(..., .envir = parent.frame())
  }
}

smg_cli_progress_step <- function(...) {
  if (!smg_should_emit("inform")) {
    FALSE
  } else {
    cli::cli_progress_step(..., .envir = parent.frame())
    TRUE
  }
}

smg_cli_progress_done <- function(step_active) {
  if (isTRUE(step_active)) cli::cli_progress_done()
}

smg_cli_abort <- function(...) {
  cli::cli_abort(..., .envir = parent.frame())
}

smg_init_verbosity()
