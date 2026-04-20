#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${HOME:-}" ]]; then
  echo "error: HOME is not set (run install_miniconda.sh as the target user with a valid login home)" >&2
  exit 1
fi
if [[ ! -d "$HOME" ]]; then
  echo "error: HOME (${HOME}) is not a directory" >&2
  exit 1
fi
if [[ ! -w "$HOME" ]]; then
  echo "error: HOME (${HOME}) is not writable by current user (uid=$(id -u), user=$(id -un))" >&2
  exit 1
fi

mc_root="${HOME}/miniconda3"
installer="${mc_root}/miniconda.sh"

case "$(uname -m)" in
  x86_64|amd64)
    mc_arch="x86_64"
    ;;
  aarch64|arm64)
    mc_arch="aarch64"
    ;;
  *)
    echo "error: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

mc_url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${mc_arch}.sh"

mkdir -p "${mc_root}"
if command -v wget >/dev/null 2>&1; then
  wget -q "${mc_url}" -O "${installer}"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "${mc_url}" -o "${installer}"
else
  echo "error: need wget or curl to download miniconda installer" >&2
  exit 1
fi

bash "${installer}" -b -u -p "${mc_root}"
rm -f "${installer}"

"${mc_root}/bin/conda" init --all
"${mc_root}/bin/conda" config --set auto_activate false
