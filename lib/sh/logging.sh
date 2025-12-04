# Shared logging helpers for bash scripts in this repository.
# Usage:
#   LOG_LIB="${LOG_LIB:-$(dirname ...)/lib/logging.sh}"
#   source "${LOG_LIB}"
#
# Optional environment variable:
#   LOG_FILE=/path/to/logfile  # when set, messages are duplicated to the file

if [[ -n "${PIPELINE_LOGGING_SH:-}" ]]; then
  return 0
fi
PIPELINE_LOGGING_SH=1

logging_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

logging_emit() {
  local stream="$1"
  shift
  local line="$*"

  if [[ -n "${LOG_FILE:-}" ]]; then
    mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
    if [[ "${stream}" == "stderr" ]]; then
      echo "${line}" | tee -a "${LOG_FILE}" >&2
    else
      echo "${line}" | tee -a "${LOG_FILE}"
    fi
  else
    if [[ "${stream}" == "stderr" ]]; then
      echo "${line}" >&2
    else
      echo "${line}"
    fi
  fi
}

log_message() {
  local level="$1"
  shift
  local ts
  ts=$(logging_timestamp)
  local line="[$ts] [$level] $*"
  if [[ "${level}" == "ERROR" ]]; then
    logging_emit "stderr" "${line}"
  else
    logging_emit "stdout" "${line}"
  fi
}

log_info() {
  log_message "INFO" "$@"
}

log_warn() {
  log_message "WARNING" "$@"
}

log_error() {
  log_message "ERROR" "$@"
}

log_step() {
  log_message "STEP" "$@"
}
