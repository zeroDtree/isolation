#!/usr/bin/env bash
# Remove a user provisioned by isolation/add-isolation-user.sh.
# Does not remove shared layout (/data/shared, /data/shared_software) or other users' data.
#
# Usage:
#   sudo DATA_ROOT=/data ./remove-isolation-user.sh USERNAME [options]
#
# Options:
#   --dry-run            print actions only
#   --keep-home          userdel without -r (leave /home/USER)
#   --keep-user-data     do not remove DATA_ROOT/<prefix>USER<suffix>
#   --force              pass userdel -f where supported (user may still be in use)
#   --ignore-missing     exit 0 if the account is already gone; may still remove user_data dir
#   -h, --help           show help
#
# Env: isolation.env (DATA_ROOT, USER_DATA_PREFIX, USER_DATA_SUFFIX, DRY_RUN)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=isolation-common.sh
source "${SCRIPT_DIR}/isolation-common.sh"

usage() {
  sed -n '1,18p' "$0" | tail -n +2
  exit 0
}

KEEP_HOME=0
KEEP_USER_DATA=0
FORCE_USERDEL=0
IGNORE_MISSING=0

require_root

[[ $# -ge 1 ]] || usage
USERNAME="$1"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      export DRY_RUN=1
      shift
      ;;
    --keep-home)
      KEEP_HOME=1
      shift
      ;;
    --keep-user-data)
      KEEP_USER_DATA=1
      shift
      ;;
    --force)
      FORCE_USERDEL=1
      shift
      ;;
    --ignore-missing)
      IGNORE_MISSING=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

valid_username "$USERNAME" || die "invalid username: $USERNAME"

USER_DATA="${DATA_ROOT}/${USER_DATA_PREFIX}${USERNAME}${USER_DATA_SUFFIX}"
DATA_ROOT_CANON="$(readlink -f "${DATA_ROOT}")"

path_is_under_data_root() {
  local p="$1"
  local c
  [[ -e "$p" ]] || return 1
  c="$(readlink -f "$p")"
  [[ "$c" == "${DATA_ROOT_CANON}" || "$c" == "${DATA_ROOT_CANON}"/* ]]
}

remove_user_data_if_configured() {
  if [[ "${KEEP_USER_DATA}" -eq 1 ]]; then
    echo "[skip] keeping user data (--keep-user-data): ${USER_DATA}"
    return 0
  fi
  if [[ ! -e "${USER_DATA}" ]]; then
    echo "note: user data dir absent: ${USER_DATA}"
    return 0
  fi
  path_is_under_data_root "${USER_DATA}" || die "refusing to remove path outside DATA_ROOT: ${USER_DATA}"
  echo "removing user data: ${USER_DATA}"
  run rm -rf "${USER_DATA}"
}

user_exists() {
  id -u "$USERNAME" &>/dev/null
}

if ! user_exists; then
  if [[ "${IGNORE_MISSING}" -eq 1 ]]; then
    echo "note: user does not exist: ${USERNAME}"
    remove_user_data_if_configured
    echo "ok: cleanup done (user already absent)"
    exit 0
  fi
  die "user does not exist: ${USERNAME} (use --ignore-missing to only drop user_data)"
fi

USERDEL_ARGS=()
[[ "${FORCE_USERDEL}" -eq 1 ]] && USERDEL_ARGS+=( -f )
[[ "${KEEP_HOME}" -eq 0 ]] && USERDEL_ARGS+=( -r )

echo "removing user: ${USERNAME}"
if [[ "${#USERDEL_ARGS[@]}" -gt 0 ]]; then
  run userdel "${USERDEL_ARGS[@]}" "${USERNAME}"
else
  run userdel "${USERNAME}"
fi

remove_user_data_if_configured

echo "ok: removed user=${USERNAME}, data_root=${DATA_ROOT}"
