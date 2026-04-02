#!/usr/bin/env bash
# One-time host layout: SOFTWARE_GROUP, SOFTWARE_ROOT with sticky+setgid (see doc/default.typ).
#
# Usage: sudo ./init-shared-software-layout.sh
# Env:   default-user-environment/config.env (override SOFTWARE_ROOT, SOFTWARE_MODE, DRY_RUN, …)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_root

if [[ "${ENABLE_SOFTWARE_AREA}" != "1" ]]; then
  echo "ENABLE_SOFTWARE_AREA is not 1; skipping shared software layout."
  exit 0
fi

run groupadd -f "${SOFTWARE_GROUP}"
run mkdir -p "${SOFTWARE_ROOT}"
run chown "root:${SOFTWARE_GROUP}" "${SOFTWARE_ROOT}"
run chmod "${SOFTWARE_MODE}" "${SOFTWARE_ROOT}"

echo "ok: ${SOFTWARE_ROOT} ready (group ${SOFTWARE_GROUP}, mode ${SOFTWARE_MODE})"
echo "    add users to the group and run apply-default-user-environment.sh for ~/software link"
