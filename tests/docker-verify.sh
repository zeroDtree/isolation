#!/usr/bin/env bash
# Run isolation repo checks inside Docker (Linux + root). Usage:
#   ./tests/docker-verify.sh [IMAGE] [--no-install-miniconda|--install-miniconda]
# Default IMAGE: ubuntu:24.04
# Env: USER_A, USER_B, USER_C (optional; default iso_a / iso_b / iso_c)
# Env: INSTALL_MINICONDA (default 1) — pass 0 or use --no-install-miniconda to skip
#      Miniconda download (needs wget/curl in the image).

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="ubuntu:24.04"
INSTALL_MINICONDA="${INSTALL_MINICONDA:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-install-miniconda)
      INSTALL_MINICONDA=0
      shift
      ;;
    --install-miniconda)
      INSTALL_MINICONDA=1
      shift
      ;;
    -*)
      echo "usage: $0 [IMAGE] [--no-install-miniconda|--install-miniconda]" >&2
      exit 1
      ;;
    *)
      IMAGE="$1"
      shift
      ;;
  esac
done

export USER_A="${USER_A:-iso_a}"
export USER_B="${USER_B:-iso_b}"
export USER_C="${USER_C:-iso_c}"
export INSTALL_MINICONDA

docker run --rm -u 0 \
  -e USER_A -e USER_B -e USER_C -e INSTALL_MINICONDA \
  -v "${REPO_ROOT}:/work" -w /work "${IMAGE}" bash /work/tests/docker-verify-inner.sh

echo "docker-verify: success"
