#!/usr/bin/env bash
# One-time host layout: DATA_ROOT, shared_ro group, SHARED_DATA_PATH per doc/main.typ
#
# Usage: sudo ./init-host.sh
# Env:   see isolation.env (override DATA_ROOT, SHARED_DATA_DIR_NAME, SHARED_DATA_PATH, SHARED_DATA_MODE, DRY_RUN, etc.)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=isolation-common.sh
source "${SCRIPT_DIR}/isolation-common.sh"

require_root

[[ "${SHARED_DATA_DIR_NAME}" != *"/"* ]] || die "SHARED_DATA_DIR_NAME must be a single path segment (no /): ${SHARED_DATA_DIR_NAME}"

run mkdir -p "${SHARED_DATA_PATH}"
run chown root:root "${DATA_ROOT}"
run chmod 755 "${DATA_ROOT}"
run groupadd -f "${SHARED_GROUP}"
run chown "root:${SHARED_GROUP}" "${SHARED_DATA_PATH}"
run chmod "${SHARED_DATA_MODE}" "${SHARED_DATA_PATH}"

echo "ok: ${SHARED_DATA_PATH} ready (group ${SHARED_GROUP}, mode ${SHARED_DATA_MODE})"
echo "    add users with add-isolation-user.sh; use --join-shared-ro to add ${SHARED_GROUP} (access per SHARED_DATA_MODE)"
