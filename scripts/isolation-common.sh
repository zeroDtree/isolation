#!/usr/bin/env bash
# Shared helpers for isolation scripts (source this file, do not execute).

set -euo pipefail

_ISOLATION_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=isolation.env
source "${_ISOLATION_COMMON_DIR}/isolation.env"

die() {
  echo "error: $*" >&2
  exit 1
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "must run as root (use sudo)"
}

valid_username() {
  local u="$1"
  [[ "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  return 0
}

get_user_uid() {
  id -u "$1" 2>/dev/null || die "user not found: $1"
}

run() {
  if [[ "${DRY_RUN}" == 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    echo
  else
    "$@"
  fi
}
