#!/usr/bin/env bash
# Apply doc/default.typ to an existing user: software group, ~/software symlink, shell templates,
# optional Miniconda. Appends umask hint to ~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish when present.
#
# Usage:
#   sudo ./apply-default-user-environment.sh USERNAME [options]
#
# Options:
#   --no-join-software     do not add user to SOFTWARE_GROUP or create ~/software link
#   --skip-templates       do not copy files from TEMPLATE_DIR
#   --force-templates      overwrite existing destination files when copying templates
#   --install-miniconda    run TEMPLATE_DIR/install_miniconda.sh as the user (needs network)
#   -h, --help             show help
#
# Env: see default-user-environment/config.env and isolation/isolation.env

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

JOIN_SOFTWARE=1
SKIP_TEMPLATES=0
FORCE_TEMPLATES=0
INSTALL_MINICONDA=0

usage() {
  sed -n '1,22p' "$0" | tail -n +2
  exit 0
}

require_root

[[ $# -ge 1 ]] || usage
USERNAME="${1:?}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-join-software)
      JOIN_SOFTWARE=0
      shift
      ;;
    --skip-templates)
      SKIP_TEMPLATES=1
      shift
      ;;
    --force-templates)
      FORCE_TEMPLATES=1
      shift
      ;;
    --install-miniconda)
      INSTALL_MINICONDA=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

valid_username "$USERNAME" || die "invalid username: $USERNAME"

if ! id -u "$USERNAME" &>/dev/null; then
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "[dry-run] skip apply: user ${USERNAME} does not exist yet (useradd was not executed in dry-run)"
    echo "ok: (dry-run) would run full apply after user exists"
    exit 0
  fi
  die "user does not exist: $USERNAME (create with isolation/add-isolation-user.sh first)"
fi

HOME_DIR="/home/${USERNAME}"

if [[ "${ENABLE_SOFTWARE_AREA}" == "1" ]] && [[ "$JOIN_SOFTWARE" -eq 1 ]]; then
  run groupadd -f "${SOFTWARE_GROUP}"
  run usermod -aG "${SOFTWARE_GROUP}" "$USERNAME"
  LINK_PATH="${HOME_DIR}/${USER_SOFTWARE_LINK_NAME}"
  run ln -sfn "${SOFTWARE_ROOT}" "${LINK_PATH}"
  run chown -h "${USERNAME}:${USERNAME}" "${LINK_PATH}"
else
  echo "[skip] software group and ~/software link (ENABLE_SOFTWARE_AREA=${ENABLE_SOFTWARE_AREA}, join=${JOIN_SOFTWARE})"
fi

if [[ "$SKIP_TEMPLATES" -eq 0 ]] && [[ -d "${TEMPLATE_DIR}" ]]; then
  copy_template() {
    local src_name="$1"
    local dst_rel="$2"
    local src="${TEMPLATE_DIR}/${src_name}"
    local dst="${HOME_DIR}/${dst_rel}"
    [[ -f "$src" ]] || return 0
    if [[ -e "$dst" ]] && [[ "$FORCE_TEMPLATES" -eq 0 ]]; then
      echo "[skip] exists: ${dst_rel}"
      return 0
    fi
    run mkdir -p "$(dirname "$dst")"
    run cp -f "$src" "$dst"
    run chown "${USERNAME}:${USERNAME}" "$dst"
  }

  copy_template "bashrc.sh" ".bashrc"
  copy_template "zshrc.sh" ".zshrc"
  copy_template "config.fish" ".config/fish/config.fish"
  if [[ -f "${TEMPLATE_DIR}/vimrc" ]]; then
    copy_template "vimrc" ".vimrc"
  elif [[ -f "${TEMPLATE_DIR}/vimrc.sh" ]]; then
    copy_template "vimrc.sh" ".vimrc"
  fi
else
  [[ "$SKIP_TEMPLATES" -eq 1 ]] && echo "[skip] templates (--skip-templates)"
  [[ ! -d "${TEMPLATE_DIR}" ]] && echo "[warn] TEMPLATE_DIR not a directory: ${TEMPLATE_DIR}"
fi

# Umask hint: append once per file if marker missing (bash, zsh, fish when file exists).
append_umask_if_needed() {
  local rc="$1"
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "[dry-run] append umask ${USER_UMASK_HINT} to ${rc} if missing marker"
    return 0
  fi
  [[ -f "$rc" ]] || return 0
  if grep -qF "${ISOLATION_BASHRC_MARK}" "$rc" 2>/dev/null; then
    return 0
  fi
  cat >>"$rc" <<EOF

${ISOLATION_BASHRC_MARK}
umask ${USER_UMASK_HINT}
EOF
  chown "${USERNAME}:${USERNAME}" "$rc"
}

append_umask_if_needed "${HOME_DIR}/.bashrc"
append_umask_if_needed "${HOME_DIR}/.zshrc"
append_umask_if_needed "${HOME_DIR}/.config/fish/config.fish"

if [[ "$INSTALL_MINICONDA" -eq 1 ]]; then
  MC="${TEMPLATE_DIR}/install_miniconda.sh"
  if [[ ! -f "$MC" ]]; then
    die "install_miniconda.sh not found: $MC"
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    echo "[dry-run] sudo -u ${USERNAME} bash ${MC}"
  else
    run sudo -u "$USERNAME" bash "$MC"
  fi
fi

echo "ok: default user environment applied for ${USERNAME}"
echo "    note: new group membership requires re-login to take effect (newgrp or log out/in)"
