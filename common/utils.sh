#!/usr/bin/env bash
# Shared helpers for isolation scripts (source this file, do not execute).

set -euo pipefail

_COMMON_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${_COMMON_UTILS_DIR}/config.env"

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

# Run a command as USER (runuser if present, else sudo -u). Honors DRY_RUN via run().
as_user() {
  local u="${1:?}"
  shift
  if command -v runuser >/dev/null 2>&1; then
    run runuser -u "$u" -- "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo -u "$u" -- "$@"
  else
    die "need runuser or sudo to run commands as another user"
  fi
}

# Append umask hint (after ISOLATION_BASHRC_MARK) if the marker is not already in the file.
# Usage: append_isolation_umask_rc USERNAME RC_PATH [CREATE]
#   CREATE=0 (default): only touch existing files; skip if RC_PATH is missing.
#   CREATE=1: mkdir -p dirname, touch RC_PATH first (new user / guaranteed rc file).
append_isolation_umask_rc() {
  local username="${1:?}"
  local rc="${2:?}"
  local create="${3:-0}"

  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "[dry-run] append umask ${USER_UMASK_HINT} to ${rc} if missing marker"
    return 0
  fi

  if [[ "$create" == 1 ]]; then
    run mkdir -p "$(dirname "$rc")"
    run touch "$rc"
  else
    [[ -f "$rc" ]] || return 0
  fi

  if grep -qF "${ISOLATION_BASHRC_MARK}" "$rc" 2>/dev/null; then
    return 0
  fi

  cat >>"$rc" <<EOF

${ISOLATION_BASHRC_MARK}
umask ${USER_UMASK_HINT}
EOF
  run chown "${username}:${username}" "$rc"
}

# Append Docker rootless env exports once (for hosts without systemd --user / pam_systemd).
# Usage: append_rootless_docker_env_rc USERNAME RC_PATH [CREATE]
#   CREATE=0: only append if RC_PATH exists
#   CREATE=1: ensure file exists (mkdir -p, touch) then append if marker missing
append_rootless_docker_env_rc() {
  local username="${1:?}"
  local rc="${2:?}"
  local create="${3:-0}"

  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "[dry-run] append rootless docker env to ${rc} if missing marker"
    return 0
  fi

  if [[ "$create" == 1 ]]; then
    run mkdir -p "$(dirname "$rc")"
    run touch "$rc"
  else
    [[ -f "$rc" ]] || return 0
  fi

  if grep -qF "${ISOLATION_ROOTLESS_DOCKER_MARK}" "$rc" 2>/dev/null; then
    return 0
  fi

  {
    echo ""
    echo "${ISOLATION_ROOTLESS_DOCKER_MARK}"
    cat <<'EOF'
# Required when systemd --user / XDG_RUNTIME_DIR is not set (see dockerd-rootless-setuptool.sh).

# get the runtime directory of the current user (e.g. /run/user/1005)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# let the Docker client point to the correct Socket location
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"

# ensure the path is correct
export PATH="/usr/bin:$PATH"
EOF
  } >>"$rc"
  run chown "${username}:${username}" "$rc"
}

# Same as append_rootless_docker_env_rc but for fish (~/.config/fish/config.fish).
# Usage: append_rootless_docker_env_fish USERNAME RC_PATH [CREATE]
append_rootless_docker_env_fish() {
  local username="${1:?}"
  local rc="${2:?}"
  local create="${3:-0}"

  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "[dry-run] append rootless docker env (fish) to ${rc} if missing marker"
    return 0
  fi

  if [[ "$create" == 1 ]]; then
    run mkdir -p "$(dirname "$rc")"
    run touch "$rc"
  else
    [[ -f "$rc" ]] || return 0
  fi

  if grep -qF "${ISOLATION_ROOTLESS_DOCKER_MARK}" "$rc" 2>/dev/null; then
    return 0
  fi

  {
    echo ""
    echo "${ISOLATION_ROOTLESS_DOCKER_MARK}"
    cat <<'EOF'
# Required when systemd --user / XDG_RUNTIME_DIR is not set (see dockerd-rootless-setuptool.sh).
set -gx XDG_RUNTIME_DIR "/run/user/$(id -u)"
set -gx PATH /usr/bin $PATH
set -gx DOCKER_HOST unix://$XDG_RUNTIME_DIR/docker.sock
EOF
  } >>"$rc"
  run chown "${username}:${username}" "$rc"
}
