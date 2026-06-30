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

# Resolve passwd(5) home directory for USER (field 6). Fails if missing or "/".
passwd_home_for_user() {
  local u="${1:?}"
  local line h
  line="$(getent passwd "$u" 2>/dev/null)" || die "cannot resolve passwd entry for user: $u"
  h="$(printf '%s\n' "$line" | cut -d: -f6)"
  [[ -n "$h" && "$h" != "/" ]] || die "invalid home in passwd for user $u: ${h:-<empty>}"
  printf '%s\n' "$h"
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

# Run COMMAND as USER with HOME / USER / LOGNAME set from passwd and cwd = that home.
# Avoids inheriting root's cwd (e.g. admin's private repo dir) which breaks conda multiprocessing.
# Usage: as_user_in_home USER cmd [args...]
as_user_in_home() {
  local u="${1:?}"
  shift
  [[ $# -ge 1 ]] || die "as_user_in_home: need command"
  local home
  home="$(passwd_home_for_user "$u")"
  if command -v runuser >/dev/null 2>&1; then
    run runuser -u "$u" -- env HOME="$home" USER="$u" LOGNAME="$u" bash -c 'cd "$HOME" || exit 1; exec "$@"' bash "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo -u "$u" -H -- env HOME="$home" USER="$u" LOGNAME="$u" bash -c 'cd "$HOME" || exit 1; exec "$@"' bash "$@"
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

# Seconds to wait for user processes to exit during account removal.
STOP_USER_TIMEOUT_SEC="${STOP_USER_TIMEOUT_SEC:-15}"

# Return 0 when USER has at least one running process.
user_has_processes() {
  local u="${1:?}"
  pgrep -u "$u" >/dev/null 2>&1
}

# Stop rootless Docker containers and user-scoped docker.service when the socket exists.
# Uses explicit DOCKER_HOST / XDG_RUNTIME_DIR (sudo -u does not load shell rc files).
stop_rootless_docker_for_user() {
  local u="${1:?}"
  local uid xdg sock docker_host cids

  uid="$(id -u "$u" 2>/dev/null)" || return 0
  xdg="/run/user/${uid}"
  sock="${xdg}/docker.sock"
  [[ -S "$sock" ]] || return 0

  docker_host="unix://${sock}"
  echo "stopping rootless docker for user=${u}"

  if [[ "${DRY_RUN:-}" == 1 ]]; then
    echo "[dry-run] stop rootless docker containers (DOCKER_HOST=${docker_host})"
    echo "[dry-run] systemctl --user stop docker (XDG_RUNTIME_DIR=${xdg})"
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    cids="$(as_user "$u" env XDG_RUNTIME_DIR="$xdg" DOCKER_HOST="$docker_host" docker ps -q 2>/dev/null || true)"
    if [[ -n "${cids}" ]]; then
      # shellcheck disable=SC2086
      as_user "$u" env XDG_RUNTIME_DIR="$xdg" DOCKER_HOST="$docker_host" docker stop ${cids} 2>/dev/null || true
    fi
  fi

  as_user "$u" env XDG_RUNTIME_DIR="$xdg" systemctl --user stop docker 2>/dev/null || true
}

_wait_for_no_user_processes() {
  local u="${1:?}"
  local timeout="${2:?}"
  local i

  for ((i = 0; i < timeout; i++)); do
    if ! user_has_processes "$u"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Gracefully stop user sessions and processes before userdel.
# Order: rootless docker -> disable-linger -> terminate-user -> SIGTERM -> SIGKILL.
stop_user_sessions_and_processes() {
  local u="${1:?}"
  local timeout="${2:-${STOP_USER_TIMEOUT_SEC}}"

  if ! user_has_processes "$u"; then
    echo "note: no processes for user=${u}; skip session stop"
    return 0
  fi

  echo "stopping sessions and processes for user=${u}"

  stop_rootless_docker_for_user "$u"

  if command -v loginctl >/dev/null 2>&1; then
    if [[ "${DRY_RUN:-}" == 1 ]]; then
      echo "[dry-run] loginctl disable-linger ${u}"
      echo "[dry-run] loginctl terminate-user ${u}"
    else
      loginctl disable-linger "$u" 2>/dev/null || true
      loginctl terminate-user "$u" 2>/dev/null || true
    fi
  fi

  if [[ "${DRY_RUN:-}" == 1 ]]; then
    echo "[dry-run] wait up to ${timeout}s for processes to exit"
    echo "[dry-run] pkill -TERM -u ${u} if still running"
    echo "[dry-run] pkill -KILL -u ${u} if still running"
    return 0
  fi

  if _wait_for_no_user_processes "$u" "$timeout"; then
    return 0
  fi

  echo "note: sending SIGTERM to remaining processes for user=${u}"
  pkill -TERM -u "$u" 2>/dev/null || true
  if _wait_for_no_user_processes "$u" "$timeout"; then
    return 0
  fi

  echo "note: sending SIGKILL to remaining processes for user=${u}"
  pkill -KILL -u "$u" 2>/dev/null || true
  if _wait_for_no_user_processes "$u" 5; then
    return 0
  fi

  echo "error: user ${u} still has running processes:" >&2
  ps -u "$u" -o pid,ppid,cmd >&2 || true
  die "cannot remove user ${u}: processes still running (see above)"
}
