#!/usr/bin/env bash
# One-shot setup wrapper:
#   1) Initialize host layout under DATA_ROOT
#   2) Create one isolated user
#
# Usage:
#   sudo ./main.sh USERNAME DATA_DIR [options]
#
# Options:
#   --join-shared-ro         add user into shared_ro group (default behavior)
#   --no-join-shared-ro      do not add user into shared_ro group
#   --uid UID                explicit UID for useradd
#   --shell PATH             login shell (default from isolation.env)
#   --dry-run                print commands only (no changes)
#   -h, --help               show help
#
# Examples:
#   sudo ./main.sh alice /data
#   sudo ./main.sh bob /mnt/research-data --no-join-shared-ro
#   sudo ./main.sh carol /data --uid 2301 --shell /bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SCRIPT="${SCRIPT_DIR}/scripts/init-host.sh"
ADD_USER_SCRIPT="${SCRIPT_DIR}/scripts/add-isolation-user.sh"

usage() {
  sed -n '1,28p' "$0" | tail -n +2
  exit 0
}

[[ $# -ge 2 ]] || usage

USERNAME="$1"
DATA_DIR="$2"
shift 2 || true

JOIN_SHARED_RO=1
DRY_RUN_FLAG=0
EXPLICIT_UID=""
SHELL_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --join-shared-ro)
      JOIN_SHARED_RO=1
      shift
      ;;
    --no-join-shared-ro)
      JOIN_SHARED_RO=0
      shift
      ;;
    --uid)
      EXPLICIT_UID="${2:?}"
      shift 2
      ;;
    --shell)
      SHELL_PATH="${2:?}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN_FLAG=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "${DATA_DIR}" != /* ]]; then
  echo "error: DATA_DIR must be an absolute path (got: ${DATA_DIR})" >&2
  exit 1
fi

[[ -x "${INIT_SCRIPT}" ]] || { echo "error: missing ${INIT_SCRIPT}" >&2; exit 1; }
[[ -x "${ADD_USER_SCRIPT}" ]] || { echo "error: missing ${ADD_USER_SCRIPT}" >&2; exit 1; }

ADD_ARGS=("${USERNAME}")
[[ "${JOIN_SHARED_RO}" -eq 1 ]] && ADD_ARGS+=("--join-shared-ro")
[[ -n "${EXPLICIT_UID}" ]] && ADD_ARGS+=("--uid" "${EXPLICIT_UID}")
[[ -n "${SHELL_PATH}" ]] && ADD_ARGS+=("--shell" "${SHELL_PATH}")

if [[ "${DRY_RUN_FLAG}" -eq 1 ]]; then
  export DRY_RUN=1
fi

echo "[step 1/2] init host layout at DATA_ROOT=${DATA_DIR}"
DATA_ROOT="${DATA_DIR}" "${INIT_SCRIPT}"

echo "[step 2/2] create isolated user ${USERNAME}"
DATA_ROOT="${DATA_DIR}" "${ADD_USER_SCRIPT}" "${ADD_ARGS[@]}"

echo "ok: setup complete for user=${USERNAME}, data_root=${DATA_DIR}"
