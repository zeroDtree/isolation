#!/usr/bin/env bash
# One-time host layout: /data, shared_ro group, /data/shared per doc/main.typ
#
# Usage: sudo ./init-host.sh
# Env:   see isolation.env (override DATA_ROOT, SHARED_MODE, DRY_RUN, etc.)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=isolation-common.sh
source "${SCRIPT_DIR}/isolation-common.sh"

require_root

run mkdir -p "${DATA_ROOT}/shared"
run chown root:root "${DATA_ROOT}"
run chmod 755 "${DATA_ROOT}"
run groupadd -f "${SHARED_GROUP}"
run chown "root:${SHARED_GROUP}" "${DATA_ROOT}/shared"
run chmod "${SHARED_MODE}" "${DATA_ROOT}/shared"

echo "ok: ${DATA_ROOT}/shared ready (group ${SHARED_GROUP}, mode ${SHARED_MODE})"
echo "    add users with add-isolation-user.sh; use --join-shared-ro to grant read via group"
