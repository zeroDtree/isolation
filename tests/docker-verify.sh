#!/usr/bin/env bash
# @help-begin
# Run isolation repo checks inside Docker (Linux + root).
#
# Usage:
#   ./tests/docker-verify.sh [IMAGE] [options]
#
# IMAGE defaults to ubuntu:24.04 when omitted (must be the first argument when given).
#
# Options:
#   --no-install-miniconda    skip Miniconda during verify (exports INSTALL_MINICONDA=0)
#   --with-install-miniconda  install Miniconda (default; clarity only)
#   -h, --help               show help
#
# Env: USER_A, USER_B, USER_C (optional; default iso_a / iso_b / iso_c)
# Env: INSTALL_MINICONDA (default 1) — set 0 or use --no-install-miniconda to skip
#      Miniconda download (needs wget/curl in the image).
# @help-end

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="ubuntu:24.04"
INSTALL_MINICONDA="${INSTALL_MINICONDA:-1}"

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  exit 0
}

case "${1:-}" in
  -h|--help)
    usage
    ;;
esac

if [[ $# -gt 0 && "$1" != -* ]]; then
  IMAGE="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-install-miniconda)
      INSTALL_MINICONDA=0
      shift
      ;;
    --with-install-miniconda)
      INSTALL_MINICONDA=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown option or unexpected argument: $1" >&2
      echo "Run: $0 --help" >&2
      exit 1
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
