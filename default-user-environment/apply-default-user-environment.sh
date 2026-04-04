#!/usr/bin/env bash
# @help-begin
# Apply doc/en/default.md to an existing user: software group, ~/shared_software symlink, ~/USER_DATA_ROOT_LINK_NAME -> DATA_ROOT,
# shell templates, optional Miniconda. Appends umask hint to ~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish when present.
#
# Usage:
#   sudo ./apply-default-user-environment.sh USERNAME [options]
#
# Options:
#   --no-join-software     do not add user to SOFTWARE_GROUP or create ~/shared_software link
#   --skip-templates          do not apply files from TEMPLATE_DIR
#   --force-templates         overwrite destination files from templates
#   --skip-existing-templates keep existing files unchanged (no append)
#                             default behavior is append template content once
#   --install-miniconda    run install_miniconda.sh from this directory as the user (needs network)
#   -h, --help             show help
#
# Env: see common/config.env (USER_DATA_ROOT_LINK_NAME, ENABLE_DATA_ROOT_LINK, …)
#      DATA_ROOT must match the data root used for this user (add-user.sh passes it; standalone: sudo DATA_ROOT=... ./apply-...)
# @help-end

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/config.env
source "${SCRIPT_DIR}/../common/config.env"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

JOIN_SOFTWARE=1
SKIP_TEMPLATES=0
FORCE_TEMPLATES=0
SKIP_EXISTING_TEMPLATES=0
INSTALL_MINICONDA=0

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  exit 0
}

require_root

[[ $# -ge 1 ]] || usage
USERNAME="${1:?}"
shift || true

# Minimal containers often have runuser but not sudo.
as_user() {
  local u="$1"
  shift
  if command -v runuser >/dev/null 2>&1; then
    run runuser -u "$u" -- "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo -u "$u" -- "$@"
  else
    die "need runuser or sudo to run commands as another user"
  fi
}

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
    --skip-existing-templates)
      SKIP_EXISTING_TEMPLATES=1
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
  echo "[skip] software group and ~/${USER_SOFTWARE_LINK_NAME} link (ENABLE_SOFTWARE_AREA=${ENABLE_SOFTWARE_AREA}, join=${JOIN_SOFTWARE})"
fi

if [[ "${ENABLE_DATA_ROOT_LINK}" == "1" ]]; then
  DATA_ROOT_LINK_PATH="${HOME_DIR}/${USER_DATA_ROOT_LINK_NAME}"
  run ln -sfn "${DATA_ROOT}" "${DATA_ROOT_LINK_PATH}"
  run chown -h "${USERNAME}:${USERNAME}" "${DATA_ROOT_LINK_PATH}"
else
  echo "[skip] ~/${USER_DATA_ROOT_LINK_NAME} -> DATA_ROOT (ENABLE_DATA_ROOT_LINK=${ENABLE_DATA_ROOT_LINK})"
fi

if [[ "$SKIP_TEMPLATES" -eq 0 ]] && [[ -d "${TEMPLATE_DIR}" ]]; then
  if [[ "$FORCE_TEMPLATES" -eq 1 ]] && [[ "$SKIP_EXISTING_TEMPLATES" -eq 1 ]]; then
    die "--force-templates and --skip-existing-templates are mutually exclusive"
  fi
  # mkdir -p runs as root; chown only the leaf file leaves parent dirs as root:root.
  chown_parents_under_home() {
    local abs_dst="$1"
    local d
    d="$(dirname "$abs_dst")"
    while [[ "$d" == "${HOME_DIR}" ]] || [[ "$d" == "${HOME_DIR}/"* ]]; do
      run chown "${USERNAME}:${USERNAME}" "$d"
      [[ "$d" == "${HOME_DIR}" ]] && break
      d="$(dirname "$d")"
    done
  }
  copy_template() {
    local src_name="$1"
    local dst_rel="$2"
    local src="${TEMPLATE_DIR}/${src_name}"
    local dst="${HOME_DIR}/${dst_rel}"
    local begin_mark="# >>> isolation template ${src_name} >>>"
    local end_mark="# <<< isolation template ${src_name} <<<"
    [[ -f "$src" ]] || return 0
    run mkdir -p "$(dirname "$dst")"
    chown_parents_under_home "$dst"
    if [[ ! -e "$dst" ]] || [[ "$FORCE_TEMPLATES" -eq 1 ]]; then
      run cp -f "$src" "$dst"
      run chown "${USERNAME}:${USERNAME}" "$dst"
      return 0
    fi
    if [[ "$SKIP_EXISTING_TEMPLATES" -eq 1 ]]; then
      echo "[skip] exists: ${dst_rel}"
      return 0
    fi

    # Default mode: append template content once to existing files.
    if [[ "${DRY_RUN}" == 1 ]]; then
      echo "[dry-run] append template block ${src_name} -> ${dst_rel} (if marker missing)"
      return 0
    fi
    if grep -qF "${begin_mark}" "$dst" 2>/dev/null; then
      echo "[skip] template block exists: ${dst_rel}"
      return 0
    fi
    {
      echo ""
      echo "${begin_mark}"
      cat "$src"
      echo "${end_mark}"
    } >>"$dst"
    chown "${USERNAME}:${USERNAME}" "$dst"
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
append_isolation_umask_rc "${USERNAME}" "${HOME_DIR}/.bashrc" 0
append_isolation_umask_rc "${USERNAME}" "${HOME_DIR}/.zshrc" 0
append_isolation_umask_rc "${USERNAME}" "${HOME_DIR}/.config/fish/config.fish" 0

if [[ "$INSTALL_MINICONDA" -eq 1 ]]; then
  MC="${SCRIPT_DIR}/install_miniconda.sh"
  if [[ ! -f "$MC" ]]; then
    die "install_miniconda.sh not found: $MC"
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    if command -v runuser >/dev/null 2>&1; then
      echo "[dry-run] runuser -u ${USERNAME} -- bash ${MC}"
    elif command -v sudo >/dev/null 2>&1; then
      echo "[dry-run] sudo -u ${USERNAME} -- bash ${MC}"
    else
      die "need runuser or sudo to run commands as another user"
    fi
  else
    as_user "$USERNAME" bash "$MC"
  fi
fi

echo "ok: default user environment applied for ${USERNAME}"
echo "    note: new group membership requires re-login to take effect (newgrp or log out/in)"
