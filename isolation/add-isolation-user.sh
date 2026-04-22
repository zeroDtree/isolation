#!/usr/bin/env bash
# @help-begin
# Create a research user with private home mode (USER_HOME_MODE; default 700).
# Directory permissions only — no CPU/memory/task limits (see doc/main.typ).
#
# Usage:
#   sudo ./add-isolation-user.sh USERNAME [options]
#
# Options:
# @help-options-begin
#   --uid UID                 explicit UID (must be free)
#   --password PASS           set login password for the new user
#   --shell PATH             login shell (default /bin/bash)
# @help-options-end
#
# Examples:
#   sudo ./add-isolation-user.sh alice
#   sudo ./add-isolation-user.sh alice --password 'S3cret!'
#
# Defaults: see common/config.env (DEFAULT_LOGIN_SHELL, USER_HOME_MODE, …)
# @help-end

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

SHELL_PATH="${DEFAULT_LOGIN_SHELL}"
EXPLICIT_UID=""
LOGIN_PASSWORD=""

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
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
# Dry-run does not create the account; getent would fail — useradd -m default is /home/NAME.
if [[ "${DRY_RUN}" == 1 ]]; then
  HOME_DIR="/home/${USERNAME}"
else
  HOME_DIR="$(passwd_home_for_user "$USERNAME")"
fi
run chmod "${USER_HOME_MODE}" "$HOME_DIR"

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

append_isolation_umask_rc "${USERNAME}" "${USER_RC}" 1

echo "ok: user ${USERNAME} (uid ${UID_VAL})"
echo "    home ${HOME_DIR} (${USER_HOME_MODE})"
