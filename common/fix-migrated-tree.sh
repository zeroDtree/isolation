#!/usr/bin/env bash
# Shared helpers for fix-migrated-shared-software.sh and fix-migrated-shared-data.sh.
# Source this file after common/config.env and common/utils.sh; do not execute.

# State for fix_migrated_tree_main (set only while it runs).
_FIX_MIGRATED_TARGET_ROOT_CANON=""

_fix_migrated_under_target_root() {
  local c="$1"
  [[ "$c" == "${_FIX_MIGRATED_TARGET_ROOT_CANON}" || "$c" == "${_FIX_MIGRATED_TARGET_ROOT_CANON}"/* ]]
}

_fix_migrated_validate_path() {
  local arg="$1"
  local c
  [[ -e "$arg" ]] || die "path does not exist: ${arg}"
  c="$(readlink -f "$arg")"
  _fix_migrated_under_target_root "$c" || die "path must be under ${FIX_MIGRATED_LABEL}=${FIX_MIGRATED_TARGET_ROOT} (resolved: ${c})"
}

# Print a single -perm MODE string for "any u/g/o execute bit" (e.g. /111 or +111).
# GNU findutils: -perm /111. Newer GNU removed +MODE; BSD find rejects /111 but accepts +111.
_fix_migrated_detect_find_perm_any_exec() {
  local d f
  d="$(mktemp -d)" || return 1
  f="${d}/t"
  touch "$f" || {
    rm -rf "$d"
    return 1
  }
  chmod 700 "$f" || {
    rm -rf "$d"
    return 1
  }
  if [[ -n "$(find "$f" -maxdepth 0 -type f -perm /111 -print 2>/dev/null)" ]]; then
    printf '/111\n'
  elif [[ -n "$(find "$f" -maxdepth 0 -type f -perm +111 -print 2>/dev/null)" ]]; then
    printf '+111\n'
  else
    rm -rf "$d"
    return 1
  fi
  rm -rf "$d"
}

# Set by fix_migrated_tree_main when --normalize-perms (any execute bit, not -111 all-three).
_FIX_MIGRATED_FIND_PERM_ANY=""

_fix_migrated_dry_run_chmods() {
  local tree="$1"
  local d f
  local pe="${_FIX_MIGRATED_FIND_PERM_ANY:?internal error: _FIX_MIGRATED_FIND_PERM_ANY not set}"
  while IFS= read -r -d '' d; do
    printf '[dry-run] chmod 2755 %q\n' "$d"
  done < <(find "$tree" -type d -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    printf '[dry-run] chmod 644 %q\n' "$f"
  done < <(find "$tree" -type f ! -perm "${pe}" -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    printf '[dry-run] chmod 755 %q\n' "$f"
  done < <(find "$tree" -type f -perm "${pe}" -print0 2>/dev/null)
}

# fix_migrated_tree_usage
#   Uses FIX_MIGRATED_HELP_SCRIPT if set, else $0 (caller wrapper).

fix_migrated_tree_usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "${FIX_MIGRATED_HELP_SCRIPT:-$0}"
  exit 1
}

# fix_migrated_tree_main "$@"
#
# Caller sets before calling:
#   FIX_MIGRATED_TARGET_ROOT              root directory path (e.g. SOFTWARE_ROOT or SHARED_DATA_PATH)
#   FIX_MIGRATED_TARGET_GROUP             Unix group name (e.g. SOFTWARE_GROUP or SHARED_GROUP)
#   FIX_MIGRATED_LABEL                    label for messages (e.g. SOFTWARE_ROOT or SHARED_DATA_PATH)
#   FIX_MIGRATED_INIT_HINT                text inside "(run ...)" for "not a directory" errors, e.g.
#                                         "init-shared-software-layout.sh first"
#   FIX_MIGRATED_REQUIRE_SOFTWARE_AREA    optional; set to 1 to require ENABLE_SOFTWARE_AREA=1
#
# Optional:
#   FIX_MIGRATED_HELP_SCRIPT              script path for --help extraction

fix_migrated_tree_main() {
  local NORMALIZE_PERMS=0
  local PATHS=()
  local arg p

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --normalize-perms)
        NORMALIZE_PERMS=1
        shift
        ;;
      -h|--help)
        fix_migrated_tree_usage
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

  [[ ${#PATHS[@]} -gt 0 ]] || fix_migrated_tree_usage

  [[ -n "${FIX_MIGRATED_TARGET_ROOT:-}" ]] || die "internal error: FIX_MIGRATED_TARGET_ROOT not set"
  [[ -n "${FIX_MIGRATED_TARGET_GROUP:-}" ]] || die "internal error: FIX_MIGRATED_TARGET_GROUP not set"
  [[ -n "${FIX_MIGRATED_LABEL:-}" ]] || die "internal error: FIX_MIGRATED_LABEL not set"
  [[ -n "${FIX_MIGRATED_INIT_HINT:-}" ]] || die "internal error: FIX_MIGRATED_INIT_HINT not set"

  require_root

  if [[ "${FIX_MIGRATED_REQUIRE_SOFTWARE_AREA:-0}" == "1" ]]; then
    if [[ "${ENABLE_SOFTWARE_AREA}" != "1" ]]; then
      die "ENABLE_SOFTWARE_AREA is not 1; refusing (shared software area disabled in config)"
    fi
  fi

  [[ -d "${FIX_MIGRATED_TARGET_ROOT}" ]] || die "${FIX_MIGRATED_LABEL} is not a directory: ${FIX_MIGRATED_TARGET_ROOT} (run ${FIX_MIGRATED_INIT_HINT})"

  _FIX_MIGRATED_TARGET_ROOT_CANON="$(readlink -f "${FIX_MIGRATED_TARGET_ROOT}")"

  run groupadd -f "${FIX_MIGRATED_TARGET_GROUP}"

  for arg in "${PATHS[@]}"; do
    _fix_migrated_validate_path "$arg"
  done

  _FIX_MIGRATED_FIND_PERM_ANY=""
  if [[ "${NORMALIZE_PERMS}" -eq 1 ]]; then
    _FIX_MIGRATED_FIND_PERM_ANY="$(_fix_migrated_detect_find_perm_any_exec)" ||
      die "find(1) does not support -perm /111 or +111 (any execute bit); cannot use --normalize-perms"
  fi

  for arg in "${PATHS[@]}"; do
    p="$(readlink -f "$arg")"
    echo "fixing: ${p}"
    run chgrp -R "${FIX_MIGRATED_TARGET_GROUP}" "$p"
    if [[ "${NORMALIZE_PERMS}" -eq 1 ]]; then
      if [[ "${DRY_RUN:-}" == 1 ]]; then
        _fix_migrated_dry_run_chmods "$p"
      else
        find "$p" -type d -exec chmod 2755 {} +
        find "$p" -type f ! -perm "${_FIX_MIGRATED_FIND_PERM_ANY}" -exec chmod 644 {} +
        find "$p" -type f -perm "${_FIX_MIGRATED_FIND_PERM_ANY}" -exec chmod 755 {} +
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
    echo "ok: chgrp ${FIX_MIGRATED_TARGET_GROUP}, normalized dirs 2755 + files 644/755 (${#PATHS[@]} path(s))"
  else
    echo "ok: group ${FIX_MIGRATED_TARGET_GROUP} and setgid on directories under ${#PATHS[@]} path(s)"
  fi
}
