#!/usr/bin/env bash
# Create a research user with home 700, /data/<user>, optional shared_ro.
# Directory permissions only — no CPU/memory/task limits (see doc/main_user.typ).
#
# Usage:
#   sudo ./add-isolation-user.sh USERNAME [options]
#
# Options:
#   --uid UID                 explicit UID (must be free)
#   --join-shared-ro         add user to shared_ro (read /data/shared)
#   --shell PATH             login shell (default /bin/bash)
#
# Examples:
#   sudo ./add-isolation-user.sh alice
#   sudo ./add-isolation-user.sh bob --join-shared-ro
#
# Defaults: see isolation.env (DATA_ROOT, DEFAULT_LOGIN_SHELL, USER_UMASK_HINT, …)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=isolation-common.sh
source "${SCRIPT_DIR}/isolation-common.sh"

JOIN_SHARED_RO=0
SHELL_PATH="${DEFAULT_LOGIN_SHELL}"
EXPLICIT_UID=""

usage() {
  sed -n '1,25p' "$0" | tail -n +2
  exit 0
}

require_root

[[ $# -ge 1 ]] || usage
USERNAME="$1"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uid)
      EXPLICIT_UID="${2:?}"
      shift 2
      ;;
    --join-shared-ro)
      JOIN_SHARED_RO=1
      shift
      ;;
    --shell)
      SHELL_PATH="${2:?}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

valid_username "$USERNAME" || die "invalid username: $USERNAME (use lowercase letters, digits, underscore; POSIX rules)"

if id -u "$USERNAME" &>/dev/null; then
  die "user already exists: $USERNAME"
fi

USERADD_ARGS=( -m -s "$SHELL_PATH" )
[[ -n "$EXPLICIT_UID" ]] && USERADD_ARGS+=( -u "$EXPLICIT_UID" )

run useradd "${USERADD_ARGS[@]}" "$USERNAME"

UID_VAL="$(get_user_uid "$USERNAME")"
HOME_DIR="/home/${USERNAME}"
USER_DATA="${DATA_ROOT}/${USERNAME}"

run mkdir -p "$USER_DATA"
run chown -R "${USERNAME}:${USERNAME}" "$USER_DATA"
run chmod 700 "$USER_DATA"
run chmod 700 "$HOME_DIR"

if [[ "$JOIN_SHARED_RO" -eq 1 ]]; then
  run groupadd -f "${SHARED_GROUP}"
  run usermod -aG "${SHARED_GROUP}" "$USERNAME"
fi

# Optional umask hint in user bashrc (append once)
if [[ "${DRY_RUN}" != 1 ]]; then
  USER_BASHRC="${HOME_DIR}/.bashrc"
  if [[ -f "$USER_BASHRC" ]] && ! grep -qF "${ISOLATION_BASHRC_MARK}" "$USER_BASHRC" 2>/dev/null; then
    cat >>"$USER_BASHRC" <<EOF

${ISOLATION_BASHRC_MARK}
umask ${USER_UMASK_HINT}
EOF
    chown "${USERNAME}:${USERNAME}" "$USER_BASHRC"
  fi
else
  echo "[dry-run] append umask ${USER_UMASK_HINT} to ${HOME_DIR}/.bashrc if missing"
fi

echo "ok: user ${USERNAME} (uid ${UID_VAL})"
echo "    home ${HOME_DIR} (700), data ${USER_DATA} (700)"
[[ "$JOIN_SHARED_RO" -eq 1 ]] && echo "    supplementary group: ${SHARED_GROUP} (/data/shared)"
