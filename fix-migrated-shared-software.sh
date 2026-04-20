#!/usr/bin/env bash
# @help-begin
# After copying a software tree into SOFTWARE_ROOT, align group and directory
# setgid so the collaborative layout matches doc/en/default.md (sticky on the
# root is already set by init-shared-software-layout.sh).
#
# Usage:
#   sudo ./fix-migrated-shared-software.sh [options] PATH [PATH ...]
#
# Options:
#   --normalize-perms   Also chmod directories to 2755 (setgid + rwxr-xr-x); files
#                       without any execute bit -> 644, with any execute bit -> 755.
#   -h, --help          show this help
#
# Default (without --normalize-perms): chgrp -R and chmod g+s on directories only;
# regular file modes are unchanged.
#
# Each PATH must lie under SOFTWARE_ROOT (absolute or relative).
#
# Env: DRY_RUN=1 to print actions only; SOFTWARE_ROOT / SOFTWARE_GROUP from common/config.env
# @help-end

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/config.env
source "${REPO_ROOT}/common/config.env"
# shellcheck source=common/utils.sh
source "${REPO_ROOT}/common/utils.sh"

FIX_MIGRATED_TARGET_ROOT="${SOFTWARE_ROOT}"
FIX_MIGRATED_TARGET_GROUP="${SOFTWARE_GROUP}"
FIX_MIGRATED_LABEL="SOFTWARE_ROOT"
FIX_MIGRATED_INIT_HINT="init-shared-software-layout.sh first"
FIX_MIGRATED_REQUIRE_SOFTWARE_AREA=1
FIX_MIGRATED_HELP_SCRIPT="${BASH_SOURCE[0]}"

# shellcheck source=common/fix-migrated-tree.sh
source "${REPO_ROOT}/common/fix-migrated-tree.sh"

fix_migrated_tree_main "$@"
