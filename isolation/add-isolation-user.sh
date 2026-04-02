#!/usr/bin/env bash
# Create a research user with home 700, /data/<prefix><user><suffix>, shared_ro by default.
# Directory permissions only — no CPU/memory/task limits (see doc/main.typ).
#
# Usage:
#   sudo ./add-isolation-user.sh USERNAME [options]
#
# Options:
#   --uid UID                 explicit UID (must be free)
#   --password PASS           set login password for the new user
#   --join-shared-ro         add user to shared_ro (default behavior)
#   --no-join-shared-ro      do not add user to shared_ro
#   --shell PATH             login shell (default /bin/bash)
#
# Examples:
#   sudo ./add-isolation-user.sh alice
#   sudo ./add-isolation-user.sh alice --password 'S3cret!'
#   sudo ./add-isolation-user.sh bob --join-shared-ro
#   sudo ./add-isolation-user.sh carol --no-join-shared-ro
#
# Defaults: see isolation.env (DATA_ROOT, USER_DATA_PREFIX, USER_DATA_SUFFIX, …)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=isolation-common.sh
source "${SCRIPT_DIR}/isolation-common.sh"

JOIN_SHARED_RO=1
SHELL_PATH="${DEFAULT_LOGIN_SHELL}"
EXPLICIT_UID=""
LOGIN_PASSWORD=""

usage() {
  sed -n '1,21p' "$0" | tail -n +2
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
    --password)
      LOGIN_PASSWORD="${2:?}"
      shift 2
      ;;
    --join-shared-ro)
      JOIN_SHARED_RO=1
      shift
      ;;
    --no-join-shared-ro)
      JOIN_SHARED_RO=0
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

valid_username "$USERNAME" || die "invalid username: $USERNAME (use lowercase letters, digits, underscore, hyphen; start with letter/underscore)"

if id -u "$USERNAME" &>/dev/null; then
  die "user already exists: $USERNAME"
fi

USERADD_ARGS=( -m -s "$SHELL_PATH" )
[[ -n "$EXPLICIT_UID" ]] && USERADD_ARGS+=( -u "$EXPLICIT_UID" )

run useradd "${USERADD_ARGS[@]}" "$USERNAME"

if [[ -n "${LOGIN_PASSWORD}" ]]; then
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "[dry-run] set login password for ${USERNAME} via chpasswd"
  else
    printf '%s:%s\n' "${USERNAME}" "${LOGIN_PASSWORD}" | chpasswd
  fi
fi

if [[ "${DRY_RUN}" == 1 ]]; then
  UID_VAL="(dry-run)"
else
  UID_VAL="$(get_user_uid "$USERNAME")"
fi
HOME_DIR="/home/${USERNAME}"
USER_DATA="${DATA_ROOT}/${USER_DATA_PREFIX}${USERNAME}${USER_DATA_SUFFIX}"

run mkdir -p "$USER_DATA"
run chown -R "${USERNAME}:${USERNAME}" "$USER_DATA"
run chmod 700 "$USER_DATA"
run chmod 700 "$HOME_DIR"

if [[ "$JOIN_SHARED_RO" -eq 1 ]]; then
  run groupadd -f "${SHARED_GROUP}"
  run usermod -aG "${SHARED_GROUP}" "$USERNAME"
fi

# Optional umask hint in shell startup config (append once)
case "${SHELL_PATH##*/}" in
  fish)
    USER_RC="${HOME_DIR}/.config/fish/config.fish"
    ;;
  zsh)
    USER_RC="${HOME_DIR}/.zshrc"
    ;;
  *)
    USER_RC="${HOME_DIR}/.bashrc"
    ;;
esac

if [[ "${DRY_RUN}" != 1 ]]; then
  run mkdir -p "$(dirname "$USER_RC")"
  run touch "$USER_RC"
  if ! grep -qF "${ISOLATION_BASHRC_MARK}" "$USER_RC" 2>/dev/null; then
    cat >>"$USER_RC" <<EOF

${ISOLATION_BASHRC_MARK}
umask ${USER_UMASK_HINT}
EOF
  fi
  run chown "${USERNAME}:${USERNAME}" "$USER_RC"
else
  echo "[dry-run] append umask ${USER_UMASK_HINT} to ${USER_RC} if missing"
fi

echo "ok: user ${USERNAME} (uid ${UID_VAL})"
echo "    home ${HOME_DIR} (700), data ${USER_DATA} (700)"
[[ "$JOIN_SHARED_RO" -eq 1 ]] && echo "    supplementary group: ${SHARED_GROUP} (/data/shared)"
