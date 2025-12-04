#!/usr/bin/env bash

# Template script for generating Mash sketches and screening source FASTQs.
# Set CHOCOPHLAN_DB in .env (see env.template) before running.

set -euo pipefail

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

DEFAULT_ENV_FILE="${PROJECT_DIR}/.env"
ENV_FILE="${ENV_FILE:-${DEFAULT_ENV_FILE}}"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "${ENV_FILE}"
  set +a
fi

if [[ -z "${CHOCOPHLAN_DB:-}" ]]; then
  echo "CHOCOPHLAN_DB is not set. Update .env based on env.template." >&2
  exit 1
fi

SKETCH="${PROJECT_DIR}/data/mapping/mash_screening/ref_db"
SCREEN_DIR="${PROJECT_DIR}/data/mapping/mash_screening"
LOG_DIR="${SCREEN_DIR}/logs"
FASTQ_DIR="${PROJECT_DIR}/data/source_fastq"
SCREEN_STATUS_LOG="${LOG_DIR}/screen_status.log"
SUMMARY_SCRIPT="${PROJECT_DIR}/tools/build_mash_mapping.R"

mkdir -p "${SCREEN_DIR}" "${LOG_DIR}"

# Discover FASTQ files up front to avoid glob pitfalls
shopt -s nullglob
FASTQ_FILES=("${FASTQ_DIR}"/*.fastq.gz)
shopt -u nullglob
FASTQ_COUNT=${#FASTQ_FILES[@]}
PENDING_FILES=()
CACHED_FILES=()
: > "${SCREEN_STATUS_LOG}"

if [[ "${FASTQ_COUNT}" -eq 0 ]]; then
  log_warn "No FASTQ files found under ${FASTQ_DIR}; screening step will be skipped."
else
  for fq in "${FASTQ_FILES[@]}"; do
    base="$(basename "${fq}" .fastq.gz)"
    out="${SCREEN_DIR}/${base}_screen.tab"
    if [[ -f "${out}" ]]; then
      CACHED_FILES+=("${fq}")
      printf "[%s] [CACHED] %s -> %s\n" \
        "$(logging_timestamp)" "${fq}" "${out}" >> "${SCREEN_STATUS_LOG}"
    else
      PENDING_FILES+=("${fq}")
      printf "[%s] [PENDING] %s -> %s\n" \
        "$(logging_timestamp)" "${fq}" "${out}" >> "${SCREEN_STATUS_LOG}"
    fi
  done
  log_warn "This script runs sequentially and may take a while."
  log_info "Found ${FASTQ_COUNT} FASTQ file(s): ${#CACHED_FILES[@]} cached, ${#PENDING_FILES[@]} pending."
  log_info "Detailed cache status logged to ${SCREEN_STATUS_LOG}"
  log_info "For faster execution, consider using the SLURM array wrapper:"
  log_info "  slurm/jobs/submit_mash_screen_array.sh"
  log_info "This parallelizes screening across multiple compute nodes."
fi

log_step "1/3 Sketching reference database from ${CHOCOPHLAN_DB%/}"
if [[ -f "${SKETCH}.msh" ]]; then
  log_info "${SKETCH}.msh already exists; remove it to rebuild the sketch."
else
  SKETCH_LOG="${LOG_DIR}/mash_sketch.log"
  TMP_FILE_LIST="${LOG_DIR}/tmp_fna_list.txt"
  log_info "Logging to ${SKETCH_LOG}"
  find "${CHOCOPHLAN_DB%/}" -name "*.fna*" -type f > "${TMP_FILE_LIST}"
  FILE_COUNT=$(wc -l < "${TMP_FILE_LIST}")
  log_info "Found ${FILE_COUNT} .fna* file(s) to sketch"
  pixi run mash sketch -l "${TMP_FILE_LIST}" -o "${SKETCH}" \
    > "${SKETCH_LOG}" 2>&1
  rm -f "${TMP_FILE_LIST}"
fi

log_step "2/3 Screening source FASTQs"
if [[ "${FASTQ_COUNT}" -gt 0 ]]; then
  if [[ "${#PENDING_FILES[@]}" -eq 0 ]]; then
    log_info "All FASTQ files already have Mash results; nothing to screen."
  else
    for fq in "${PENDING_FILES[@]}"; do
      base="$(basename "${fq}" .fastq.gz)"
      out="${SCREEN_DIR}/${base}_screen.tab"
      err_log="${LOG_DIR}/${base}_screen.log"
      log_info "Screening ${fq} -> ${out} (stderr → ${err_log})"
      pixi run mash screen "${SKETCH}.msh" "${fq}" > "${out}" 2> "${err_log}"
    done
  fi
else
  log_info "No FASTQ inputs detected; nothing to screen."
fi

log_step "3/3 Summarizing results"
pixi run Rscript "${SUMMARY_SCRIPT}" --quiet

log_info "Done. Review ${SCREEN_DIR}/*.tab and ${PROJECT_DIR}/data/mapping/mash.tsv"
