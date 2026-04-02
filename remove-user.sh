#!/usr/bin/env bash
# Remove a user created by main.sh: deletes the account (and by default home + /data/<user>_data).
# Does not undo host init (shared data dir under DATA_ROOT, /data/shared_software) or shared trees.
#
# Usage:
#   sudo ./remove-user.sh USERNAME DATA_DIR [options]
#
# Options are passed to isolation/remove-isolation-user.sh:
#   --dry-run, --keep-home, --keep-user-data, --force, --ignore-missing, -h, --help
#
# Examples:
#   sudo ./remove-user.sh alice /data
#   sudo ./remove-user.sh bob /data --dry-run
#   sudo ./remove-user.sh carol /mnt/research-data --keep-user-data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVE_SCRIPT="${SCRIPT_DIR}/isolation/remove-isolation-user.sh"

usage() {
  sed -n '1,16p' "$0" | tail -n +2
  exit 0
}

[[ $# -ge 2 ]] || usage

USERNAME="$1"
DATA_DIR="$2"
shift 2 || true

if [[ "${DATA_DIR}" != /* ]]; then
  echo "error: DATA_DIR must be an absolute path (got: ${DATA_DIR})" >&2
  exit 1
fi

[[ -x "${REMOVE_SCRIPT}" ]] || { echo "error: missing ${REMOVE_SCRIPT}" >&2; exit 1; }

case "${1:-}" in
  -h|--help)
    usage
    ;;
esac

DATA_ROOT="${DATA_DIR}" "${REMOVE_SCRIPT}" "${USERNAME}" "$@"
