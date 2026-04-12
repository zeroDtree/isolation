#!/usr/bin/env bash
# @help-begin
# Create a research user with private home and data dir modes (USER_HOME_MODE, USER_DATA_DIR_MODE; default 700), shared-data group by default.
# Directory permissions only — no CPU/memory/task limits (see doc/main.typ).
#
# Usage:
#   sudo ./add-isolation-user.sh USERNAME [options]
#
# Options:
# @help-options-begin
#   --uid UID                 explicit UID (must be free)
#   --password PASS           set login password for the new user
#   --join-shared-data-group   add user to SHARED_GROUP for shared datasets (default behavior)
#   --no-join-shared-data-group do not add user to SHARED_GROUP
#   --shell PATH             login shell (default /bin/bash)
# @help-options-end
#
# Examples:
#   sudo ./add-isolation-user.sh alice
#   sudo ./add-isolation-user.sh alice --password 'S3cret!'
#   sudo ./add-isolation-user.sh bob --join-shared-data-group
#   sudo ./add-isolation-user.sh carol --no-join-shared-data-group
#
# Defaults: see common/config.env (DATA_ROOT, USER_HOME_MODE, USER_DATA_DIR_MODE, …)
# @help-end

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

JOIN_SHARED_DATA_GROUP=1
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
    --join-shared-data-group)
      JOIN_SHARED_DATA_GROUP=1
      shift
      ;;
    --no-join-shared-data-group)
      JOIN_SHARED_DATA_GROUP=0
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
run chmod "${USER_DATA_DIR_MODE}" "$USER_DATA"
run chmod "${USER_HOME_MODE}" "$HOME_DIR"

if [[ "$JOIN_SHARED_DATA_GROUP" -eq 1 ]]; then
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

append_isolation_umask_rc "${USERNAME}" "${USER_RC}" 1

echo "ok: user ${USERNAME} (uid ${UID_VAL})"
echo "    home ${HOME_DIR} (${USER_HOME_MODE}), data ${USER_DATA} (${USER_DATA_DIR_MODE})"
[[ "$JOIN_SHARED_DATA_GROUP" -eq 1 ]] && echo "    supplementary group: ${SHARED_GROUP} (${SHARED_DATA_PATH})"
