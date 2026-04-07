#!/usr/bin/env bash
# @help-begin
# After copying a dataset tree into SHARED_DATA_PATH, align group and directory
# setgid so the layout matches doc/en/add-user.md (mode on the root is already
# set by isolation/init-host.sh).
#
# Usage:
#   sudo ./fix-migrated-shared-data.sh [options] PATH [PATH ...]
#
# Options:
#   --normalize-perms   Also chmod directories to 2755 (setgid + rwxr-xr-x); files
#                       without +x -> 644, files with any +x -> 755 (644 pass first).
#   -h, --help          show this help
#
# Default (without --normalize-perms): chgrp -R and chmod g+s on directories only;
# regular file modes are unchanged.
#
# Each PATH must lie under SHARED_DATA_PATH (absolute or relative).
#
# Env: DRY_RUN=1 to print actions only; SHARED_DATA_PATH / SHARED_GROUP from common/config.env
# @help-end

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/config.env
source "${REPO_ROOT}/common/config.env"
# shellcheck source=common/utils.sh
source "${REPO_ROOT}/common/utils.sh"

FIX_MIGRATED_TARGET_ROOT="${SHARED_DATA_PATH}"
FIX_MIGRATED_TARGET_GROUP="${SHARED_GROUP}"
FIX_MIGRATED_LABEL="SHARED_DATA_PATH"
FIX_MIGRATED_INIT_HINT="isolation/init-host.sh first"
FIX_MIGRATED_HELP_SCRIPT="${BASH_SOURCE[0]}"

# shellcheck source=common/fix-migrated-tree.sh
source "${REPO_ROOT}/common/fix-migrated-tree.sh"

fix_migrated_tree_main "$@"
