#!/usr/bin/env bash
# @help-begin
# Run Docker rootless setup (dockerd-rootless-setuptool.sh install) as an existing user.
# Host must have docker-ce-rootless-extras (and uidmap); see docker/ubuntu/docker_install.sh.
# Does not run docker_rootless_prepare.sh (host-wide root docker disable).
#
# After setuptool, appends XDG_RUNTIME_DIR / PATH / DOCKER_HOST to ~/.bashrc, ~/.zshrc (if present),
# and ~/.config/fish/config.fish when missing, so login shells work without systemd user session.
#
# Usage:
#   sudo ./install-rootless-docker-for-user.sh USERNAME
#
# Env: DRY_RUN=1 — print actions only (from add-user.sh --dry-run)
# @help-end

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../common/config.env
source "${SCRIPT_DIR}/../../common/config.env"
# shellcheck source=../../common/utils.sh
source "${SCRIPT_DIR}/../../common/utils.sh"

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  exit 0
}

[[ $# -ge 1 ]] || usage
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi
USERNAME="${1:?}"
shift || true

[[ $# -eq 0 ]] || die "unexpected arguments: $*"

require_root

valid_username "$USERNAME" || die "invalid username: $USERNAME"

if ! id -u "$USERNAME" &>/dev/null; then
  if [[ "${DRY_RUN:-}" == 1 ]]; then
    echo "[dry-run] skip rootless docker: user ${USERNAME} does not exist yet"
    exit 0
  fi
  die "user does not exist: $USERNAME"
fi

SETUPTOOL="$(command -v dockerd-rootless-setuptool.sh 2>/dev/null || true)"
[[ -n "${SETUPTOOL}" ]] || die "dockerd-rootless-setuptool.sh not found; install docker-ce-rootless-extras (see docker/ubuntu/docker_install.sh)"

if ! grep -q "^${USERNAME}:" /etc/subuid 2>/dev/null; then
  die "no /etc/subuid entry for ${USERNAME}; assign subuids (e.g. usermod --add-subuids) or adjust login.defs / use adduser"
fi
if ! grep -q "^${USERNAME}:" /etc/subgid 2>/dev/null; then
  die "no /etc/subgid entry for ${USERNAME}; assign subgids (e.g. usermod --add-subgids)"
fi

if command -v loginctl >/dev/null 2>&1; then
  run loginctl enable-linger "$USERNAME"
else
  echo "warning: loginctl not found; skipping enable-linger (user systemd units may need an active login)" >&2
fi

as_user "$USERNAME" "${SETUPTOOL}" install

USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
[[ -n "${USER_HOME}" && "${USER_HOME}" != "/" ]] || die "cannot resolve home directory for ${USERNAME}"

append_rootless_docker_env_rc "$USERNAME" "${USER_HOME}/.bashrc" 1
append_rootless_docker_env_rc "$USERNAME" "${USER_HOME}/.zshrc" 0
append_rootless_docker_env_fish "$USERNAME" "${USER_HOME}/.config/fish/config.fish" 1

echo "ok: rootless docker setuptool install ran for user=${USERNAME}"
echo "    if systemd --user is unavailable: new login shell or reload rc (source ~/.bashrc; in fish: exec fish), then start the daemon, e.g."
echo "      dockerd-rootless.sh &"
echo "    (context \"rootless\" and DOCKER_HOST are configured; see Docker rootless docs for linger/systemd user units)"
