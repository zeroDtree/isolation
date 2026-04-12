#!/usr/bin/env bash
# @help-begin
# Run init-shared-software-layout then apply-default-user-environment for one user.
#
# Usage:
#   sudo ./run-default-user-environment.sh USERNAME [apply-options...]
#
# Apply options are passed through to apply-default-user-environment.sh (e.g. --no-join-shared-software-group,
# --skip-templates, --with-templates, --force-templates, --with-install-miniconda).
#
# Env: DATA_ROOT and others apply to isolation scripts only if you chain with add-user.sh separately;
# for this wrapper, init uses SOFTWARE_* from common/config.env.
# @help-end

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  awk '/^# @help-begin$/{f=1; next} /^# @help-end$/{f=0} f' "$0"
  exit 1
}

[[ $# -ge 1 ]] || usage
USERNAME="$1"
shift || true

INIT="${SCRIPT_DIR}/init-shared-software-layout.sh"
APPLY="${SCRIPT_DIR}/apply-default-user-environment.sh"

echo "[step 1/2] init shared software layout"
"${INIT}"

echo "[step 2/2] apply default user environment for ${USERNAME}"
"${APPLY}" "${USERNAME}" "$@"

echo "ok: run-default-user-environment complete for ${USERNAME}"
