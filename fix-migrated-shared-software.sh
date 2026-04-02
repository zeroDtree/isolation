#!/usr/bin/env bash
# After copying a software tree into SOFTWARE_ROOT, align group and directory
# setgid so the collaborative layout matches doc/en/default.typ (sticky on the
# root is already set by init-shared-software-layout.sh).
#
# Usage:
#   sudo ./fix-migrated-shared-software.sh [options] PATH [PATH ...]
#
# Options:
#   --normalize-perms   Also chmod directories to 2755 (setgid + rwxr-xr-x); files
#                       without +x -> 644, files with any +x -> 755 (644 pass first).
#
# Default (without --normalize-perms): chgrp -R and chmod g+s on directories only;
# regular file modes are unchanged.
#
# Each PATH must lie under SOFTWARE_ROOT (absolute or relative).
#
# Env: DRY_RUN=1 to print actions only; SOFTWARE_ROOT / SOFTWARE_GROUP from config.env

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=default-user-environment/common.sh
source "${REPO_ROOT}/default-user-environment/common.sh"

NORMALIZE_PERMS=0
PATHS=()

usage() {
  echo "usage: sudo $0 [--normalize-perms] PATH [PATH ...]" >&2
  echo "  Default: chgrp -R ${SOFTWARE_GROUP} and chmod g+s on directories." >&2
  echo "  --normalize-perms: dirs 2755; non-exec files 644, then +x files 755." >&2
  echo "  Each PATH must be inside SOFTWARE_ROOT (${SOFTWARE_ROOT})." >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --normalize-perms)
      NORMALIZE_PERMS=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      die "unknown option: $1 (try --help)"
      ;;
    *)
      PATHS+=("$1")
      shift
      ;;
  esac
done

[[ ${#PATHS[@]} -gt 0 ]] || usage

require_root

if [[ "${ENABLE_SOFTWARE_AREA}" != "1" ]]; then
  die "ENABLE_SOFTWARE_AREA is not 1; refusing (shared software area disabled in config)"
fi

[[ -d "${SOFTWARE_ROOT}" ]] || die "SOFTWARE_ROOT is not a directory: ${SOFTWARE_ROOT} (run init-shared-software-layout.sh first)"

SOFTWARE_ROOT_CANON="$(readlink -f "${SOFTWARE_ROOT}")"

under_software_root() {
  local c="$1"
  [[ "$c" == "${SOFTWARE_ROOT_CANON}" || "$c" == "${SOFTWARE_ROOT_CANON}"/* ]]
}

validate_path() {
  local arg="$1"
  local c
  [[ -e "$arg" ]] || die "path does not exist: ${arg}"
  c="$(readlink -f "$arg")"
  under_software_root "$c" || die "path must be under SOFTWARE_ROOT=${SOFTWARE_ROOT} (resolved: ${c})"
}

dry_run_chmods() {
  local p="$1"
  local d f
  while IFS= read -r -d '' d; do
    printf '[dry-run] chmod 2755 %q\n' "$d"
  done < <(find "$p" -type d -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    printf '[dry-run] chmod 644 %q\n' "$f"
  done < <(find "$p" -type f ! -perm -111 -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    printf '[dry-run] chmod 755 %q\n' "$f"
  done < <(find "$p" -type f -perm -111 -print0 2>/dev/null)
}

run groupadd -f "${SOFTWARE_GROUP}"

for arg in "${PATHS[@]}"; do
  validate_path "$arg"
done

for arg in "${PATHS[@]}"; do
  p="$(readlink -f "$arg")"
  echo "fixing: ${p}"
  run chgrp -R "${SOFTWARE_GROUP}" "$p"
  if [[ "${NORMALIZE_PERMS}" -eq 1 ]]; then
    if [[ "${DRY_RUN:-}" == 1 ]]; then
      dry_run_chmods "$p"
    else
      find "$p" -type d -exec chmod 2755 {} +
      find "$p" -type f ! -perm -111 -exec chmod 644 {} +
      find "$p" -type f -perm -111 -exec chmod 755 {} +
    fi
  else
    if [[ "${DRY_RUN:-}" == 1 ]]; then
      while IFS= read -r -d '' d; do
        printf '[dry-run] chmod g+s %q\n' "$d"
      done < <(find "$p" -type d -print0 2>/dev/null)
    else
      find "$p" -type d -exec chmod g+s {} +
    fi
  fi
done

if [[ "${NORMALIZE_PERMS}" -eq 1 ]]; then
  echo "ok: chgrp ${SOFTWARE_GROUP}, normalized dirs 2755 + files 644/755 (${#PATHS[@]} path(s))"
else
  echo "ok: group ${SOFTWARE_GROUP} and setgid on directories under ${#PATHS[@]} path(s)"
fi
