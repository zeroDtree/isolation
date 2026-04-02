#!/usr/bin/env bash
# Run isolation repo checks inside Docker (Linux + root). Usage:
#   ./tests/docker-verify.sh [IMAGE]
# Default IMAGE: ubuntu:24.04
# Env: USER_A, USER_B, USER_C (optional; default iso_a / iso_b / iso_c)

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:-ubuntu:24.04}"
export USER_A="${USER_A:-iso_a}"
export USER_B="${USER_B:-iso_b}"
export USER_C="${USER_C:-iso_c}"

docker run --rm -u 0 -e USER_A -e USER_B -e USER_C -v "${REPO_ROOT}:/work" -w /work "${IMAGE}" bash /work/tests/docker-verify-inner.sh

echo "docker-verify: success"
