#!/usr/bin/env bash
# Shared helpers for default-user-environment scripts (source this file).

set -euo pipefail

_DUE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
source "${_DUE_DIR}/config.env"
# shellcheck source=../isolation/isolation-common.sh
source "${_DUE_DIR}/../isolation/isolation-common.sh"
