#!/usr/bin/env bash
# @help-begin
# Remove a user created by add-user.sh: deletes the account (and by default home + DATA_ROOT/<user>_data).
# Does not undo host init (shared data dir under DATA_ROOT, shared software tree) or shared trees.
#
# Usage:
#   sudo ./remove-user.sh USERNAME [options]
#
# Env: DATA_ROOT — must match the root used when the user was added (default from common/config.env).
#
# Options are passed to isolation/remove-isolation-user.sh:
#   --dry-run, --keep-home, --keep-user-data, --force, --ignore-missing, -h, --help
#
# Examples:
#   sudo ./remove-user.sh alice
#   sudo ./remove-user.sh bob --dry-run
#   sudo DATA_ROOT=/mnt/research-data ./remove-user.sh carol --keep-user-data
# @help-end

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/config.env
source "${SCRIPT_DIR}/common/config.env"
REMOVE_SCRIPT="${SCRIPT_DIR}/isolation/remove-isolation-user.sh"

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
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

if [[ "${DATA_ROOT}" != /* ]]; then
  echo "error: DATA_ROOT must be an absolute path (got: ${DATA_ROOT}); set DATA_ROOT or edit common/config.env" >&2
  exit 1
fi

[[ -x "${REMOVE_SCRIPT}" ]] || { echo "error: missing ${REMOVE_SCRIPT}" >&2; exit 1; }

case "${1:-}" in
  -h|--help)
    usage
    ;;
esac

DATA_ROOT="${DATA_ROOT}" "${REMOVE_SCRIPT}" "${USERNAME}" "$@"
