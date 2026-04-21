#!/usr/bin/env bash
# @help-begin
# Apply doc/en/default.md to an existing user: software group, ~/shared_software symlink, ~/USER_DATA_ROOT_LINK_NAME -> DATA_ROOT,
# optional ~/.cache symlink into per-user private data (ENABLE_USER_CACHE_LINK, USER_CACHE_BACKING_NAME),
# shell templates, optional Miniconda. Appends umask hint to ~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish when present.
#
# Usage:
#   sudo ./apply-default-user-environment.sh USERNAME [options]
#
# Options:
# @help-options-begin
#   --no-join-shared-software-group  do not add user to SOFTWARE_GROUP or create ~/shared_software link
#   --with-join-shared-software-group add to SOFTWARE_GROUP and ~/shared_software (default; clarity only)
#   --no-user-cache-link   do not symlink ~/.cache to private USER_DATA cache directory
#   --with-user-cache-link symlink ~/.cache when ENABLE_USER_CACHE_LINK=1 (default; clarity after --no-user-cache-link)
#   --skip-templates          do not apply files from TEMPLATE_DIR
#   --with-templates          apply files from TEMPLATE_DIR (default; clarity after --skip-templates)
#   --force-templates         overwrite destination files from templates
#   --no-force-templates      merge/replace per default rules (default; clarity after --force-templates)
#   --skip-existing-templates keep existing files unchanged (no merge/replace)
#   --no-skip-existing-templates default merge/replace behavior (clarity after --skip-existing-templates)
#                             default: append if no marker, else replace isolation template block(s)
#   --install-miniconda    same as --with-install-miniconda
#   --with-install-miniconda copy template/shell_utils -> ~/shell_utils, run install_miniconda.sh as the user (needs network)
#   --no-install-miniconda skip Miniconda install (default)
#   -h, --help             show help
# @help-options-end
#
# Env: see common/config.env (USER_DATA_ROOT_LINK_NAME, ENABLE_DATA_ROOT_LINK, ENABLE_USER_CACHE_LINK, USER_CACHE_BACKING_NAME, …)
#      DATA_ROOT must match the data root used for this user (same as add-user.sh / common/config.env; standalone: sudo DATA_ROOT=... ./apply-...)
# @help-end

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/config.env
source "${SCRIPT_DIR}/../common/config.env"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

JOIN_SOFTWARE=1
JOIN_USER_CACHE_LINK=1
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-join-shared-software-group)
      JOIN_SOFTWARE=0
      shift
      ;;
    --with-join-shared-software-group)
      JOIN_SOFTWARE=1
      shift
      ;;
    --no-user-cache-link)
      JOIN_USER_CACHE_LINK=0
      shift
      ;;
    --with-user-cache-link)
      JOIN_USER_CACHE_LINK=1
      shift
      ;;
    --skip-templates)
      SKIP_TEMPLATES=1
      shift
      ;;
    --with-templates)
      SKIP_TEMPLATES=0
      shift
      ;;
    --force-templates)
      FORCE_TEMPLATES=1
      shift
      ;;
    --no-force-templates)
      FORCE_TEMPLATES=0
      shift
      ;;
    --skip-existing-templates)
      SKIP_EXISTING_TEMPLATES=1
      shift
      ;;
    --no-skip-existing-templates)
      SKIP_EXISTING_TEMPLATES=0
      shift
      ;;
    --install-miniconda|--with-install-miniconda)
      INSTALL_MINICONDA=1
      shift
      ;;
    --no-install-miniconda)
      INSTALL_MINICONDA=0
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

HOME_DIR="$(passwd_home_for_user "$USERNAME")"

if [[ "${ENABLE_SOFTWARE_AREA}" == "1" ]] && [[ "$JOIN_SOFTWARE" -eq 1 ]]; then
  run groupadd -f "${SOFTWARE_GROUP}"
  run usermod -aG "${SOFTWARE_GROUP}" "$USERNAME"
  LINK_PATH="${HOME_DIR}/${USER_SOFTWARE_LINK_NAME}"
  run ln -sfn "${SOFTWARE_ROOT}" "${LINK_PATH}"
  run chown -h "${USERNAME}:${USERNAME}" "${LINK_PATH}"
else
  echo "[skip] software group and ~/${USER_SOFTWARE_LINK_NAME} link (ENABLE_SOFTWARE_AREA=${ENABLE_SOFTWARE_AREA}, join=${JOIN_SOFTWARE})"
fi

if [[ "${ENABLE_SOFTWARE_AREA}" == "1" ]]; then
  CUDA_SHARED_DIR="${SOFTWARE_ROOT}/cuda"
  if [[ -e "${CUDA_SHARED_DIR}" ]] && [[ ! -d "${CUDA_SHARED_DIR}" ]]; then
    die "shared cuda path exists and is not a directory: ${CUDA_SHARED_DIR}"
  fi
  # 3775 keeps this directory collaborative for SOFTWARE_GROUP and preserves group on new files.
  run mkdir -p "${CUDA_SHARED_DIR}"
  run chown "root:${SOFTWARE_GROUP}" "${CUDA_SHARED_DIR}"
  run chmod 3775 "${CUDA_SHARED_DIR}"
fi

if [[ "${ENABLE_DATA_ROOT_LINK}" == "1" ]]; then
  DATA_ROOT_LINK_PATH="${HOME_DIR}/${USER_DATA_ROOT_LINK_NAME}"
  run ln -sfn "${DATA_ROOT}" "${DATA_ROOT_LINK_PATH}"
  run chown -h "${USERNAME}:${USERNAME}" "${DATA_ROOT_LINK_PATH}"
else
  echo "[skip] ~/${USER_DATA_ROOT_LINK_NAME} -> DATA_ROOT (ENABLE_DATA_ROOT_LINK=${ENABLE_DATA_ROOT_LINK})"
fi

if [[ "${ENABLE_USER_CACHE_LINK}" == "1" ]] && [[ "${JOIN_USER_CACHE_LINK}" -eq 1 ]]; then
  USER_DATA="${DATA_ROOT}/${USER_DATA_PREFIX}${USERNAME}${USER_DATA_SUFFIX}"
  USER_CACHE_DIR="${USER_DATA}/${USER_CACHE_BACKING_NAME}"
  CACHE_LINK="${HOME_DIR}/.cache"

  ensure_user_private_data_root() {
    run mkdir -p "${USER_DATA}"
    run chown -R "${USERNAME}:${USERNAME}" "${USER_DATA}"
    run chmod "${USER_DATA_DIR_MODE}" "${USER_DATA}"
  }

  ensure_backing_cache_dir() {
    run mkdir -p "${USER_CACHE_DIR}"
    run chown "${USERNAME}:${USERNAME}" "${USER_CACHE_DIR}"
    run chmod "${USER_DATA_DIR_MODE}" "${USER_CACHE_DIR}"
  }

  link_home_cache_to_backing() {
    run ln -sfn "${USER_CACHE_DIR}" "${CACHE_LINK}"
    run chown -h "${USERNAME}:${USERNAME}" "${CACHE_LINK}"
  }

  if [[ -L "${CACHE_LINK}" ]] || [[ ! -e "${CACHE_LINK}" ]]; then
    ensure_user_private_data_root
    ensure_backing_cache_dir
    link_home_cache_to_backing
  elif [[ -d "${CACHE_LINK}" ]]; then
    ensure_user_private_data_root
    if [[ -e "${USER_CACHE_DIR}" ]]; then
      die "refusing ~/.cache -> ${USER_CACHE_DIR}: ${CACHE_LINK} is a directory and backing path already exists; merge or remove one manually"
    fi
    if [[ "${DRY_RUN}" == 1 ]]; then
      echo "[dry-run] mv ${CACHE_LINK} ${USER_CACHE_DIR} then symlink ~/.cache -> ${USER_CACHE_DIR}"
    else
      run mv "${CACHE_LINK}" "${USER_CACHE_DIR}"
      run chown -R "${USERNAME}:${USERNAME}" "${USER_CACHE_DIR}"
      run chmod "${USER_DATA_DIR_MODE}" "${USER_CACHE_DIR}"
      link_home_cache_to_backing
    fi
  else
    die "refusing ~/.cache -> ${USER_CACHE_DIR}: ${CACHE_LINK} exists and is not a directory or symlink (remove or relocate it)"
  fi
else
  echo "[skip] ~/.cache -> USER_DATA/${USER_CACHE_BACKING_NAME} (ENABLE_USER_CACHE_LINK=${ENABLE_USER_CACHE_LINK}, join=${JOIN_USER_CACHE_LINK})"
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
    local begin_mark end_mark
    case "${src_name}" in
      vimrc|vimrc.sh)
        # Vim line comments start with ". Bash/zsh/fish use #.
        begin_mark="\" >>> isolation template ${src_name} >>>"
        end_mark="\" <<< isolation template ${src_name} <<<"
        ;;
      *)
        begin_mark="# >>> isolation template ${src_name} >>>"
        end_mark="# <<< isolation template ${src_name} <<<"
        ;;
    esac
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

    # Default mode: append template block once, or replace existing marked block(s).
    # Boundary markers use # for shell configs and " for vimrc (see case above).
    local block_tmp
    block_tmp="$(mktemp)"
    {
      echo ""
      echo "${begin_mark}"
      echo ""
      cat "$src"
      echo ""
      echo "${end_mark}"
      echo ""
    } >"${block_tmp}"

    if [[ "${DRY_RUN}" == 1 ]]; then
      if grep -qF "${begin_mark}" "$dst" 2>/dev/null; then
        echo "[dry-run] replace template block ${src_name} -> ${dst_rel}"
      else
        echo "[dry-run] append template block ${src_name} -> ${dst_rel}"
      fi
      rm -f "${block_tmp}"
      return 0
    fi

    if grep -qF "${begin_mark}" "$dst" 2>/dev/null; then
      local out_tmp
      out_tmp="$(mktemp)"
      if ! awk -v begin="${begin_mark}" -v end="${end_mark}" -v newf="${block_tmp}" '
BEGIN { state=0 }
state==0 && $0==begin {
  state=1
  while ((getline line < newf) > 0) print line
  close(newf)
  next
}
state==0 { print; next }
state==1 && $0==end { state=0; next }
state==1 { next }
END { if (state==1) exit 1 }
' "$dst" >"${out_tmp}"; then
        rm -f "${block_tmp}" "${out_tmp}"
        die "isolation template ${src_name}: unclosed block in ${dst_rel} (missing ${end_mark})"
      fi
      rm -f "${block_tmp}"
      mv -f "${out_tmp}" "$dst"
      chown "${USERNAME}:${USERNAME}" "$dst"
      return 0
    fi

    cat "${block_tmp}" >>"$dst"
    rm -f "${block_tmp}"
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
  SU_SRC="${TEMPLATE_DIR}/shell_utils"
  SU_DST="${HOME_DIR}/shell_utils"
  MC_DST="${SU_DST}/install_miniconda.sh"
  if [[ ! -d "$SU_SRC" ]] || [[ ! -f "${SU_SRC}/install_miniconda.sh" ]]; then
    die "template shell_utils missing or incomplete: ${SU_SRC} (need install_miniconda.sh)"
  fi
  run mkdir -p "${HOME_DIR}"
  run rm -rf "${SU_DST}"
  # Follow symlinks so ~/shell_utils is real files (symlinks into the repo break for other users).
  run cp -aL "${SU_SRC}" "${SU_DST}"
  run chown -R "${USERNAME}:${USERNAME}" "${SU_DST}"
  run chmod +x "${MC_DST}"
  as_user_in_home "$USERNAME" bash "$MC_DST"
fi

echo "ok: default user environment applied for ${USERNAME}"
echo "    note: new group membership requires re-login to take effect (newgrp or log out/in)"
