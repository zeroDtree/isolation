#!/usr/bin/env bash
# One-shot setup wrapper:
#   1) Initialize host layout under DATA_ROOT
#   2) Create one isolated user
#   3) Init shared software tree (doc/default.typ) and apply templates / ~/software link
#
# Usage:
#   sudo ./add-user.sh USERNAME DATA_DIR [options]
#
# Options:
#   --join-shared-ro         add user into shared_ro group (default behavior)
#   --no-join-shared-ro      do not add user into shared_ro group
#   --uid UID                explicit UID for useradd
#   --password PASS          set login password for the new user
#   --shell PATH             login shell (default from isolation.env)
#   --dry-run                print commands only (no changes)
#   --no-default-user-env    skip shared-software init and apply-default-user-environment.sh
#   --with-default-user-env  run default user env (default; for clarity only)
#   --no-join-software       pass through: do not add to SOFTWARE_GROUP or ~/software
#   --skip-templates         pass through: do not apply files from TEMPLATE_DIR
#   --force-templates        pass through: overwrite existing rc files from templates
#   --skip-existing-templates pass through: keep existing files unchanged (no append)
#   --install-miniconda      pass through: run template/install_miniconda.sh as user
#   -h, --help               show help
#
# Examples:
#   sudo ./add-user.sh alice /data
#   sudo ./add-user.sh alice /data --password 'S3cret!'
#   sudo ./add-user.sh bob /mnt/research-data --no-join-shared-ro
#   sudo ./add-user.sh carol /data --uid 2301 --shell /bin/zsh
#   sudo ./add-user.sh dave /data --no-default-user-env
#   sudo ./add-user.sh eve /data --install-miniconda

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SCRIPT="${SCRIPT_DIR}/isolation/init-host.sh"
ADD_USER_SCRIPT="${SCRIPT_DIR}/isolation/add-isolation-user.sh"
INIT_SHARED_SOFTWARE="${SCRIPT_DIR}/default-user-environment/init-shared-software-layout.sh"
APPLY_DEFAULT_ENV="${SCRIPT_DIR}/default-user-environment/apply-default-user-environment.sh"

usage() {
  sed -n '1,33p' "$0" | tail -n +2
  exit 0
}

[[ $# -ge 2 ]] || usage

USERNAME="$1"
DATA_DIR="$2"
shift 2 || true

JOIN_SHARED_RO=1
DRY_RUN_FLAG=0
EXPLICIT_UID=""
LOGIN_PASSWORD=""
SHELL_PATH=""
DEFAULT_USER_ENV=1
APPLY_ARGS=()

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
    --password)
      LOGIN_PASSWORD="${2:?}"
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
    --no-default-user-env)
      DEFAULT_USER_ENV=0
      shift
      ;;
    --with-default-user-env)
      DEFAULT_USER_ENV=1
      shift
      ;;
    --no-join-software|--skip-templates|--force-templates|--skip-existing-templates|--install-miniconda)
      APPLY_ARGS+=("$1")
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
if [[ "${DEFAULT_USER_ENV}" -eq 1 ]]; then
  [[ -x "${INIT_SHARED_SOFTWARE}" ]] || { echo "error: missing ${INIT_SHARED_SOFTWARE}" >&2; exit 1; }
  [[ -x "${APPLY_DEFAULT_ENV}" ]] || { echo "error: missing ${APPLY_DEFAULT_ENV}" >&2; exit 1; }
fi

ADD_ARGS=("${USERNAME}")
[[ "${JOIN_SHARED_RO}" -eq 1 ]] && ADD_ARGS+=("--join-shared-ro")
[[ -n "${EXPLICIT_UID}" ]] && ADD_ARGS+=("--uid" "${EXPLICIT_UID}")
[[ -n "${LOGIN_PASSWORD}" ]] && ADD_ARGS+=("--password" "${LOGIN_PASSWORD}")
[[ -n "${SHELL_PATH}" ]] && ADD_ARGS+=("--shell" "${SHELL_PATH}")

if [[ "${DRY_RUN_FLAG}" -eq 1 ]]; then
  export DRY_RUN=1
fi

if [[ "${DEFAULT_USER_ENV}" -eq 1 ]]; then
  _TOTAL=4
else
  _TOTAL=2
fi

echo "[step 1/${_TOTAL}] init host layout at DATA_ROOT=${DATA_DIR}"
DATA_ROOT="${DATA_DIR}" "${INIT_SCRIPT}"

echo "[step 2/${_TOTAL}] create isolated user ${USERNAME}"
DATA_ROOT="${DATA_DIR}" "${ADD_USER_SCRIPT}" "${ADD_ARGS[@]}"

if [[ "${DEFAULT_USER_ENV}" -eq 1 ]]; then
  echo "[step 3/${_TOTAL}] init shared software layout (doc/default.typ)"
  "${INIT_SHARED_SOFTWARE}"

  echo "[step 4/${_TOTAL}] apply default user environment for ${USERNAME}"
  "${APPLY_DEFAULT_ENV}" "${USERNAME}" "${APPLY_ARGS[@]}"
else
  echo "[skip] default user environment (--no-default-user-env)"
fi

echo "ok: setup complete for user=${USERNAME}, data_root=${DATA_DIR}"
