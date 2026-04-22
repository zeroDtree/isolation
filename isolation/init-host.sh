#!/usr/bin/env bash
# One-time host layout: DATA_ROOT, SHARED_GROUP (default shared_data), SHARED_DATA_PATH per doc/main.typ
#
# Usage: sudo ./init-host.sh
# Env:   see common/config.env (override DATA_ROOT, SHARED_DATA_DIR_NAME, SHARED_DATA_PATH, SHARED_DATA_MODE, DRY_RUN, etc.)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

require_root

[[ "${SHARED_DATA_DIR_NAME}" != *"/"* ]] || die "SHARED_DATA_DIR_NAME must be a single path segment (no /): ${SHARED_DATA_DIR_NAME}"

run mkdir -p "${SHARED_DATA_PATH}"
run chown root:root "${DATA_ROOT}"
run chmod 755 "${DATA_ROOT}"
run groupadd -f "${SHARED_GROUP}"
run chown "root:${SHARED_GROUP}" "${SHARED_DATA_PATH}"
run chmod "${SHARED_DATA_MODE}" "${SHARED_DATA_PATH}"

echo "ok: ${SHARED_DATA_PATH} ready (group ${SHARED_GROUP}, mode ${SHARED_DATA_MODE})"
echo "    create users with isolation/add-isolation-user.sh; then run default-user-environment/apply-default-user-environment.sh"
echo "    (or use add-user.sh) to join ${SHARED_GROUP} by default (use --no-join-shared-data-group to skip)"
