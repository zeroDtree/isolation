#!/usr/bin/env bash
# @help-begin
# One-shot setup wrapper:
#   1) Initialize host layout under DATA_ROOT (isolation/init-host.sh)
#   2) Create one isolated user (isolation/add-isolation-user.sh)
#   3) Init shared software layout and apply default user env (default-user-environment/*)
#
# Usage:
#   sudo ./add-user.sh USERNAME [options]
#
# Env: DATA_ROOT — absolute data root (default from common/config.env). Example:
#   sudo DATA_ROOT=/mnt/research-data ./add-user.sh alice
#   ENABLE_USER_CACHE_LINK and related keys — see common/config.env and apply-default-user-environment.sh (options below).
#
# Wrapper options:
#   --dry-run                 print commands only (exports DRY_RUN=1 for child scripts)
#   --no-default-user-env     skip shared-software init and apply-default-user-environment.sh
#   --with-default-user-env   run default user env (default)
#   --with-install-rootless-docker  run docker/ubuntu/install-rootless-docker-for-user.sh after setup
#   --no-install-rootless-docker    skip rootless Docker prep (default)
#   -h, --help                show help
#
# If no options are passed, the default behavior is equivalent to:
#   sudo ./add-user.sh USERNAME --join-shared-data-group --with-default-user-env --with-join-shared-software-group --with-templates --no-force-templates --no-skip-existing-templates --with-user-cache-link --no-install-miniconda --no-install-rootless-docker

# @help-end

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/config.env
source "${SCRIPT_DIR}/common/config.env"

INIT_SCRIPT="${SCRIPT_DIR}/isolation/init-host.sh"
ADD_USER_SCRIPT="${SCRIPT_DIR}/isolation/add-isolation-user.sh"
INIT_SHARED_SOFTWARE="${SCRIPT_DIR}/default-user-environment/init-shared-software-layout.sh"
APPLY_DEFAULT_ENV="${SCRIPT_DIR}/default-user-environment/apply-default-user-environment.sh"
INSTALL_ROOTLESS_DOCKER_SCRIPT="${SCRIPT_DIR}/docker/ubuntu/install-rootless-docker-for-user.sh"

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  printf '%s\n' \
    '#' \
    '# Options forwarded to isolation/add-isolation-user.sh:' \
    '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "${ADD_USER_SCRIPT}"
  printf '%s\n' \
    '#' \
    '# Options forwarded to default-user-environment/apply-default-user-environment.sh (when not using --no-default-user-env):' \
    '#'
  awk '/^# @help-options-begin$/{f=1; next} /^# @help-options-end$/{f=0} f' "${APPLY_DEFAULT_ENV}"
  exit 0
}

[[ $# -ge 1 ]] || usage
case "${1:-}" in
  -h|--help)
    usage
    ;;
esac

USERNAME="$1"
shift

PASS_ADD_ISOLATION=()
PASS_APPLY_DEFAULT=()
DRY_RUN_FLAG=0
DEFAULT_USER_ENV=1
INSTALL_ROOTLESS_DOCKER=0
USER_ALREADY_EXISTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --with-install-rootless-docker)
      INSTALL_ROOTLESS_DOCKER=1
      shift
      ;;
    --no-install-rootless-docker)
      INSTALL_ROOTLESS_DOCKER=0
      shift
      ;;
    # Pass through to add-isolation-user.sh
    --uid|--password|--shell)
      PASS_ADD_ISOLATION+=("$1" "${2:?}")
      shift 2
      ;;
    # Pass through to apply-default-user-environment.sh
    --join-shared-data-group|--no-join-shared-data-group|--no-join-shared-software-group|--with-join-shared-software-group|--skip-templates|--with-templates|--force-templates|--no-force-templates|--skip-existing-templates|--no-skip-existing-templates|--with-install-miniconda|--no-install-miniconda|--no-user-cache-link|--with-user-cache-link)
      PASS_APPLY_DEFAULT+=("$1")
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

if [[ "${DATA_ROOT}" != /* ]]; then
  echo "error: DATA_ROOT must be an absolute path (got: ${DATA_ROOT}); set DATA_ROOT or edit common/config.env" >&2
  exit 1
fi

[[ -x "${INIT_SCRIPT}" ]] || { echo "error: missing ${INIT_SCRIPT}" >&2; exit 1; }
[[ -x "${ADD_USER_SCRIPT}" ]] || { echo "error: missing ${ADD_USER_SCRIPT}" >&2; exit 1; }
if [[ "${DEFAULT_USER_ENV}" -eq 1 ]]; then
  [[ -x "${INIT_SHARED_SOFTWARE}" ]] || { echo "error: missing ${INIT_SHARED_SOFTWARE}" >&2; exit 1; }
  [[ -x "${APPLY_DEFAULT_ENV}" ]] || { echo "error: missing ${APPLY_DEFAULT_ENV}" >&2; exit 1; }
fi
if [[ "${INSTALL_ROOTLESS_DOCKER}" -eq 1 ]]; then
  [[ -x "${INSTALL_ROOTLESS_DOCKER_SCRIPT}" ]] || { echo "error: missing ${INSTALL_ROOTLESS_DOCKER_SCRIPT}" >&2; exit 1; }
fi

if [[ "${DRY_RUN_FLAG}" -eq 1 ]]; then
  export DRY_RUN=1
fi

if id -u "${USERNAME}" >/dev/null 2>&1; then
  USER_ALREADY_EXISTS=1
fi

_TOTAL=2
[[ "${DEFAULT_USER_ENV}" -eq 1 ]] && _TOTAL=$((_TOTAL + 2))
[[ "${INSTALL_ROOTLESS_DOCKER}" -eq 1 ]] && _TOTAL=$((_TOTAL + 1))

_S=0
_S=$((_S + 1))
echo "[step ${_S}/${_TOTAL}] init host layout at DATA_ROOT=${DATA_ROOT}"
DATA_ROOT="${DATA_ROOT}" "${INIT_SCRIPT}"

_S=$((_S + 1))
if [[ "${USER_ALREADY_EXISTS}" -eq 1 ]]; then
  echo "[step ${_S}/${_TOTAL}] skip create isolated user ${USERNAME} (already exists)"
else
  echo "[step ${_S}/${_TOTAL}] create isolated user ${USERNAME}"
  DATA_ROOT="${DATA_ROOT}" "${ADD_USER_SCRIPT}" "${USERNAME}" "${PASS_ADD_ISOLATION[@]}"
fi

if [[ "${DEFAULT_USER_ENV}" -eq 1 ]]; then
  _S=$((_S + 1))
  echo "[step ${_S}/${_TOTAL}] init shared software layout"
  DATA_ROOT="${DATA_ROOT}" "${INIT_SHARED_SOFTWARE}"

  _S=$((_S + 1))
  echo "[step ${_S}/${_TOTAL}] apply default user environment for ${USERNAME}"
  DATA_ROOT="${DATA_ROOT}" "${APPLY_DEFAULT_ENV}" "${USERNAME}" "${PASS_APPLY_DEFAULT[@]}"
else
  echo "[skip] default user environment (--no-default-user-env)"
fi

if [[ "${INSTALL_ROOTLESS_DOCKER}" -eq 1 ]]; then
  _S=$((_S + 1))
  echo "[step ${_S}/${_TOTAL}] prepare rootless docker for ${USERNAME}"
  "${INSTALL_ROOTLESS_DOCKER_SCRIPT}" "${USERNAME}"
fi

echo "ok: setup complete for user=${USERNAME}, data_root=${DATA_ROOT}"
