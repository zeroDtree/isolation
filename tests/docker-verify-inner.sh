#!/usr/bin/env bash
# Invoked inside Docker as root; workspace mounted at /work.
# Validates permissions against doc/main.typ and doc/en/default.md (isolation, shared_ro, 3775 sticky).
# Env: INSTALL_MINICONDA (default 1) — set 0 to skip add-user.sh --install-miniconda and conda checks.
set -euo pipefail

USER_A="${USER_A:-iso_a}"
USER_B="${USER_B:-iso_b}"
USER_C="${USER_C:-iso_c}"
USER_PW="${USER_PW:-iso_pw}"
USER_PW_PASS="${USER_PW_PASS:-TestPw_123!}"
INSTALL_MINICONDA="${INSTALL_MINICONDA:-1}"

want_miniconda() {
  case "${INSTALL_MINICONDA}" in
    0|no|false|NO|FALSE|off|OFF) return 1 ;;
    *) return 0 ;;
  esac
}

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

expect_fail() {
  local desc="$1"
  shift
  if "$@"; then
    fail "expected failure: ${desc}"
  fi
  ok "expected failure: ${desc}"
}

cd /work
chmod +x add-user.sh remove-user.sh fix-migrated-shared-software.sh isolation/*.sh default-user-environment/*.sh template/shell_utils/*.sh 2>/dev/null || true

# shellcheck source=common/config.env
source /work/common/config.env
# shellcheck source=common/utils.sh
source /work/common/utils.sh

for u in "${USER_A}" "${USER_B}" "${USER_C}" "${USER_PW}"; do
  id "${u}" &>/dev/null && userdel -r "${u}" 2>/dev/null || true
done

echo "=== provision ${USER_A} and ${USER_B} (full add-user.sh) ==="
if want_miniconda; then
  echo "    (INSTALL_MINICONDA: install miniconda for ${USER_A})"
  ./add-user.sh "${USER_A}" --install-miniconda
else
  echo "    (INSTALL_MINICONDA=0: skip --install-miniconda for ${USER_A})"
  ./add-user.sh "${USER_A}"
fi
./add-user.sh "${USER_B}" --skip-templates

echo "=== add user with explicit password ==="
./add-user.sh "${USER_PW}" --password "${USER_PW_PASS}" --no-default-user-env
pw_hash="$(getent shadow "${USER_PW}" | cut -d: -f2)"
[[ -n "${pw_hash}" ]] || fail "${USER_PW} has empty password hash field"
[[ "${pw_hash}" != "!" && "${pw_hash}" != "*" && "${pw_hash}" != "!!" && "${pw_hash}" != "!*" ]] || \
  fail "${USER_PW} password should be set, got locked marker: ${pw_hash}"
ok "user password is set for ${USER_PW} (shadow entry is not locked)"

echo "=== doc/main.typ: /data and layout ==="
[[ "$(stat -c '%a' /data)" == "755" ]] || fail "/data mode want 755 got $(stat -c '%a' /data)"
ok "/data mode 755 (root:root)"

[[ "$(stat -c '%a' "${SHARED_DATA_PATH}")" == "3775" ]] || fail "${SHARED_DATA_PATH} mode want 3775 got $(stat -c '%a' "${SHARED_DATA_PATH}")"
perm_shared="$(stat -c '%A' "${SHARED_DATA_PATH}")"
[[ "${perm_shared}" == *t* ]] || fail "${SHARED_DATA_PATH} sticky bit (t) not shown in ${perm_shared}"
[[ "${perm_shared}" == *s* ]] || fail "${SHARED_DATA_PATH} setgid bit (s) not shown in ${perm_shared}"
ok "${SHARED_DATA_PATH} mode 3775 (sticky + setgid)"

[[ "$(stat -c '%U:%G' "${SHARED_DATA_PATH}")" == "root:shared_ro" ]] || fail "${SHARED_DATA_PATH} owner want root:shared_ro"
ok "${SHARED_DATA_PATH} group shared_ro"

echo "=== doc/main.typ: home and private data 700, cross-user deny ==="
for u in "${USER_A}" "${USER_B}"; do
  [[ "$(stat -c '%a' "/home/${u}")" == "700" ]] || fail "/home/${u} mode want 700"
  [[ "$(stat -c '%a' "/data/${u}_data")" == "700" ]] || fail "/data/${u}_data mode want 700"
  [[ "$(stat -c '%U' "/data/${u}_data")" == "${u}" ]] || fail "/data/${u}_data owner"
done
ok "homes and *_data are 700 and user-owned"

expect_fail "${USER_A} cannot ls ${USER_B} home" \
  as_user "${USER_A}" ls "/home/${USER_B}" 2>/dev/null

expect_fail "${USER_A} cannot read ${USER_B} file in home" \
  as_user "${USER_A}" test -r "/home/${USER_B}/.bashrc" 2>/dev/null

expect_fail "${USER_A} cannot list ${USER_B} private data dir" \
  as_user "${USER_A}" ls "/data/${USER_B}_data" 2>/dev/null

echo "=== doc/en/default.md: /data/shared_software 3775 (setgid + sticky) ==="
sw="/data/shared_software"
[[ "$(stat -c '%a' "${sw}")" == "3775" ]] || fail "${sw} mode want 3775 got $(stat -c '%a' "${sw}")"
# Sticky and setgid bits (stat %a four-digit octal on GNU stat)
[[ "$(stat -c '%a' "${sw}")" == "3775" ]] || fail "mode"
perm="$(stat -c '%A' "${sw}")"
echo "    ${sw} -> ${perm}"
[[ "${perm}" == *t* ]] || fail "sticky bit (t) not shown in ${perm}"
[[ "${perm}" == *s* ]] || fail "setgid bit (s) not shown in ${perm}"
ok "${sw} is 3775 with sticky + setgid (symbolic check)"

for u in "${USER_A}" "${USER_B}"; do
  id "${u}" | grep -q software || fail "${u} not in software group"
done
ok "both users in software group"

echo "=== doc/en/default.md: sticky — cannot unlink peer file; can read ==="
as_user "${USER_A}" touch "${sw}/file_by_${USER_A}"
as_user "${USER_A}" chmod 664 "${sw}/file_by_${USER_A}" 2>/dev/null || true

expect_fail "${USER_B} cannot delete ${USER_A}'s file (sticky)" \
  as_user "${USER_B}" rm -f "${sw}/file_by_${USER_A}" 2>/dev/null

as_user "${USER_B}" test -r "${sw}/file_by_${USER_A}" || fail "${USER_B} should read ${USER_A}'s file (group read)"
ok "${USER_B} can read peer file in shared_software"

echo "=== setgid: new entries inherit group software ==="
as_user "${USER_A}" mkdir -p "${sw}/dir_by_${USER_A}"
[[ "$(stat -c '%G' "${sw}/dir_by_${USER_A}")" == "software" ]] || \
  fail "new dir group want software got $(stat -c '%G' "${sw}/dir_by_${USER_A}")"
ok "new subdirectory group is software (setgid)"

echo "=== fix-migrated-shared-software.sh (default: chgrp + g+s on dirs) ==="
MIG_TREE="${sw}/_test_fix_migrate_tree"
rm -rf "${MIG_TREE}"
mkdir -p "${MIG_TREE}/sub/deep"
touch "${MIG_TREE}/readme.txt"
touch "${MIG_TREE}/sub/run.sh"
chmod +x "${MIG_TREE}/sub/run.sh"
chgrp -R root "${MIG_TREE}"
find "${MIG_TREE}" -type d -exec chmod g-s {} +
find "${MIG_TREE}" -type d -exec chmod 755 {} +

./fix-migrated-shared-software.sh "${MIG_TREE}"
[[ "$(stat -c '%G' "${MIG_TREE}/readme.txt")" == "software" ]] || fail "migrated file group should be software"
[[ "$(stat -c '%G' "${MIG_TREE}/sub")" == "software" ]] || fail "migrated sub dir group should be software"
perm_mig_sub="$(stat -c '%A' "${MIG_TREE}/sub")"
[[ "${perm_mig_sub}" == *s* ]] || fail "migrated sub dir should have setgid, got ${perm_mig_sub}"
as_user "${USER_A}" test -x "${MIG_TREE}/sub/run.sh" || fail "${USER_A} should run preserved executable after default fix"
ok "fix-migrated-shared-software default: chgrp software + g+s on dirs"

echo "=== fix-migrated-shared-software.sh (--normalize-perms) ==="
NORM_TREE="${sw}/_test_fix_normalize_tree"
rm -rf "${NORM_TREE}"
mkdir -p "${NORM_TREE}/bin"
echo hi > "${NORM_TREE}/data.txt"
printf '#!/bin/sh\necho x\n' > "${NORM_TREE}/bin/tool"
chmod +x "${NORM_TREE}/bin/tool"
chmod 777 "${NORM_TREE}/bin"
chgrp -R root "${NORM_TREE}"
find "${NORM_TREE}" -type d -exec chmod g-s {} +

./fix-migrated-shared-software.sh --normalize-perms "${NORM_TREE}"
[[ "$(stat -c '%a' "${NORM_TREE}/bin")" == "2755" ]] || fail "norm bin dir want 2755 got $(stat -c '%a' "${NORM_TREE}/bin")"
[[ "$(stat -c '%a' "${NORM_TREE}/data.txt")" == "644" ]] || fail "norm data want 644 got $(stat -c '%a' "${NORM_TREE}/data.txt")"
[[ "$(stat -c '%a' "${NORM_TREE}/bin/tool")" == "755" ]] || fail "norm tool want 755 got $(stat -c '%a' "${NORM_TREE}/bin/tool")"
as_user "${USER_A}" test -x "${NORM_TREE}/bin/tool" || fail "${USER_A} should execute normalized tool"
ok "fix-migrated-shared-software --normalize-perms 2755/644/755"

echo "=== fix-migrated-shared-software.sh rejects path outside SOFTWARE_ROOT ==="
expect_fail "fix script rejects /tmp" \
  ./fix-migrated-shared-software.sh /tmp

echo "=== user without software: cannot create in shared_software ==="
useradd -m -s /bin/bash "${USER_C}" 2>/dev/null || true
usermod -aG shared_ro "${USER_C}" || true
# not in group software
id "${USER_C}" | grep -q software && fail "${USER_C} should not be in software for this test" || true

expect_fail "${USER_C} (no software) cannot create in ${sw}" \
  as_user "${USER_C}" touch "${sw}/by_${USER_C}" 2>/dev/null

echo "=== doc/en/default.md: ~/${USER_SOFTWARE_LINK_NAME} symlink ==="
for u in "${USER_A}" "${USER_B}"; do
  link="/home/${u}/${USER_SOFTWARE_LINK_NAME}"
  [[ -L "${link}" ]] || fail "${link} not symlink"
  [[ "$(readlink -f "${link}")" == "${sw}" ]] || fail "symlink target"
  [[ "$(stat -c '%U:%G' "${link}")" == "${u}:${u}" ]] || fail "symlink lchown"
done
ok "~/${USER_SOFTWARE_LINK_NAME} -> ${sw}, owned by user"

echo "=== doc/en/default.md: ~/${USER_DATA_ROOT_LINK_NAME} -> DATA_ROOT ==="
for u in "${USER_A}" "${USER_B}"; do
  dr_link="/home/${u}/${USER_DATA_ROOT_LINK_NAME}"
  [[ -L "${dr_link}" ]] || fail "${dr_link} not symlink"
  [[ "$(readlink -f "${dr_link}")" == "$(readlink -f "${DATA_ROOT}")" ]] || fail "DATA_ROOT symlink target"
  [[ "$(stat -c '%U:%G' "${dr_link}")" == "${u}:${u}" ]] || fail "DATA_ROOT symlink lchown"
done
ok "~/${USER_DATA_ROOT_LINK_NAME} -> ${DATA_ROOT}, owned by user"

if want_miniconda; then
  echo "=== miniconda: --install-miniconda for ${USER_A} ==="
  as_user "${USER_A}" test -x "/home/${USER_A}/shell_utils/install_miniconda.sh" || \
    fail "~/shell_utils/install_miniconda.sh missing or not executable for ${USER_A}"
  mc_root="/home/${USER_A}/miniconda3"
  mc_conda="${mc_root}/bin/conda"
  [[ -x "${mc_conda}" ]] || fail "missing conda executable: ${mc_conda}"
  [[ ! -e "${mc_root}/miniconda.sh" ]] || fail "installer script should be removed: ${mc_root}/miniconda.sh"
  as_user "${USER_A}" "${mc_conda}" --version >/dev/null || fail "conda is not runnable for ${USER_A}"
  as_user "${USER_A}" test -f "/home/${USER_A}/.condarc" || fail ".condarc not created for ${USER_A}"
  as_user "${USER_A}" grep -Eq "auto_activate:[[:space:]]*false" "/home/${USER_A}/.condarc" || \
    fail ".condarc should contain auto_activate: false"
  ok "miniconda installed and configured for ${USER_A}"
else
  echo "=== miniconda: skipped (INSTALL_MINICONDA=0) ==="
fi

echo "=== templates: append(default), skip-existing, force overwrite ==="
bashrc_a="/home/${USER_A}/.bashrc"
tpl_mark="# >>> isolation template bashrc.sh >>>"

# Default mode appends once and should stay idempotent.
count_mark="$(grep -cF "${tpl_mark}" "${bashrc_a}" || true)"
[[ "${count_mark}" == "1" ]] || fail "default append should add one template block, got ${count_mark}"
./default-user-environment/apply-default-user-environment.sh "${USER_A}" >/dev/null
count_mark="$(grep -cF "${tpl_mark}" "${bashrc_a}" || true)"
[[ "${count_mark}" == "1" ]] || fail "re-apply default should keep one template block, got ${count_mark}"
ok "default template: append once, re-apply replaces block (idempotent marker count)"

# skip-existing mode should preserve existing file content.
before_sum="$(sha256sum "${bashrc_a}" | awk '{print $1}')"
./default-user-environment/apply-default-user-environment.sh "${USER_A}" --skip-existing-templates >/dev/null
after_sum="$(sha256sum "${bashrc_a}" | awk '{print $1}')"
[[ "${before_sum}" == "${after_sum}" ]] || fail "--skip-existing-templates should not modify existing .bashrc"
ok "--skip-existing-templates keeps existing file unchanged"

# force mode should overwrite existing content from template.
as_user "${USER_A}" bash -lc 'echo "__ISOLATION_FORCE_SENTINEL__" >> ~/.bashrc'
./default-user-environment/apply-default-user-environment.sh "${USER_A}" --force-templates >/dev/null
expect_fail "force overwrite removes previous custom sentinel in .bashrc" \
  grep -q "__ISOLATION_FORCE_SENTINEL__" "${bashrc_a}"
ok "--force-templates overwrites existing .bashrc content"

echo "=== remove-user.sh ==="
expect_fail "remove-user rejects relative DATA_ROOT" \
  env DATA_ROOT=relative/path ./remove-user.sh "${USER_A}" 2>/dev/null
./remove-user.sh nosuchuser_zz --ignore-missing
ok "remove-user --ignore-missing when account absent"
./remove-user.sh nosuchuser_zz --dry-run --ignore-missing
ok "remove-user dry-run with --ignore-missing"

echo "=== cleanup ==="
rm -f "${sw}/file_by_${USER_A}"
rm -rf "${sw}/dir_by_${USER_A}" "${sw}/_test_fix_migrate_tree" "${sw}/_test_fix_normalize_tree"
userdel -r "${USER_C}" 2>/dev/null || true
userdel -r "${USER_A}" 2>/dev/null || true
userdel -r "${USER_B}" 2>/dev/null || true
userdel -r "${USER_PW}" 2>/dev/null || true

echo "=== all permission checks passed (add-user.md + default.md) ==="
