#!/usr/bin/env bash
# Invoked inside Docker as root; workspace mounted at /work.
# Validates permissions against doc/main.typ and doc/default.typ (isolation, shared_ro, 3775 sticky).
set -euo pipefail

USER_A="${USER_A:-iso_a}"
USER_B="${USER_B:-iso_b}"
USER_C="${USER_C:-iso_c}"
USER_PW="${USER_PW:-iso_pw}"
USER_PW_PASS="${USER_PW_PASS:-TestPw_123!}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

# Minimal containers often have runuser but not sudo.
as_user() {
  local u="$1"
  shift
  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$u" -- "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "$u" -- "$@"
  else
    fail "need runuser or sudo to run commands as another user"
  fi
}

expect_fail() {
  local desc="$1"
  shift
  if "$@"; then
    fail "expected failure: ${desc}"
  fi
  ok "expected failure: ${desc}"
}

cd /work
chmod +x main.sh isolation/*.sh default-user-environment/*.sh 2>/dev/null || true

for u in "${USER_A}" "${USER_B}" "${USER_C}" "${USER_PW}"; do
  id "${u}" &>/dev/null && userdel -r "${u}" 2>/dev/null || true
done

echo "=== provision ${USER_A} and ${USER_B} (full main.sh) ==="
./main.sh "${USER_A}" /data --install-miniconda
./main.sh "${USER_B}" /data --skip-templates

echo "=== add user with explicit password ==="
./main.sh "${USER_PW}" /data --password "${USER_PW_PASS}" --no-default-user-env
pw_hash="$(getent shadow "${USER_PW}" | cut -d: -f2)"
[[ -n "${pw_hash}" ]] || fail "${USER_PW} has empty password hash field"
[[ "${pw_hash}" != "!" && "${pw_hash}" != "*" && "${pw_hash}" != "!!" && "${pw_hash}" != "!*" ]] || \
  fail "${USER_PW} password should be set, got locked marker: ${pw_hash}"
ok "user password is set for ${USER_PW} (shadow entry is not locked)"

echo "=== doc/main.typ: /data and layout ==="
[[ "$(stat -c '%a' /data)" == "755" ]] || fail "/data mode want 755 got $(stat -c '%a' /data)"
ok "/data mode 755 (root:root)"

[[ "$(stat -c '%a' /data/shared)" == "2775" ]] || fail "/data/shared mode want 2775 got $(stat -c '%a' /data/shared)"
ok "/data/shared mode 2775"

[[ "$(stat -c '%U:%G' /data/shared)" == "root:shared_ro" ]] || fail "/data/shared owner want root:shared_ro"
ok "/data/shared group shared_ro"

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

echo "=== doc/default.typ: /data/shared_software 3775 (setgid + sticky) ==="
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

echo "=== doc/default.typ: sticky — cannot unlink peer file; can read ==="
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

echo "=== user without software: cannot create in shared_software ==="
useradd -m -s /bin/bash "${USER_C}" 2>/dev/null || true
usermod -aG shared_ro "${USER_C}" || true
# not in group software
id "${USER_C}" | grep -q software && fail "${USER_C} should not be in software for this test" || true

expect_fail "${USER_C} (no software) cannot create in ${sw}" \
  as_user "${USER_C}" touch "${sw}/by_${USER_C}" 2>/dev/null

echo "=== doc/default.typ: ~/software symlink ==="
for u in "${USER_A}" "${USER_B}"; do
  [[ -L "/home/${u}/software" ]] || fail "/home/${u}/software not symlink"
  [[ "$(readlink -f "/home/${u}/software")" == "${sw}" ]] || fail "symlink target"
  [[ "$(stat -c '%U:%G' "/home/${u}/software")" == "${u}:${u}" ]] || fail "symlink lchown"
done
ok "~/software -> ${sw}, owned by user"

echo "=== miniconda: --install-miniconda for ${USER_A} ==="
mc_root="/home/${USER_A}/miniconda3"
mc_conda="${mc_root}/bin/conda"
[[ -x "${mc_conda}" ]] || fail "missing conda executable: ${mc_conda}"
[[ ! -e "${mc_root}/miniconda.sh" ]] || fail "installer script should be removed: ${mc_root}/miniconda.sh"
as_user "${USER_A}" "${mc_conda}" --version >/dev/null || fail "conda is not runnable for ${USER_A}"
as_user "${USER_A}" test -f "/home/${USER_A}/.condarc" || fail ".condarc not created for ${USER_A}"
as_user "${USER_A}" grep -Eq "auto_activate:[[:space:]]*false" "/home/${USER_A}/.condarc" || \
  fail ".condarc should contain auto_activate: false"
ok "miniconda installed and configured for ${USER_A}"

echo "=== templates: append(default), skip-existing, force overwrite ==="
bashrc_a="/home/${USER_A}/.bashrc"
tpl_mark="# >>> isolation template bashrc.sh >>>"

# Default mode appends once and should stay idempotent.
count_mark="$(grep -cF "${tpl_mark}" "${bashrc_a}" || true)"
[[ "${count_mark}" == "1" ]] || fail "default append should add one template block, got ${count_mark}"
./default-user-environment/apply-default-user-environment.sh "${USER_A}" >/dev/null
count_mark="$(grep -cF "${tpl_mark}" "${bashrc_a}" || true)"
[[ "${count_mark}" == "1" ]] || fail "re-apply default should keep one template block, got ${count_mark}"
ok "default template append is one-time and idempotent"

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

echo "=== cleanup ==="
rm -f "${sw}/file_by_${USER_A}"
rm -rf "${sw}/dir_by_${USER_A}"
userdel -r "${USER_C}" 2>/dev/null || true
userdel -r "${USER_A}" 2>/dev/null || true
userdel -r "${USER_B}" 2>/dev/null || true
userdel -r "${USER_PW}" 2>/dev/null || true

echo "=== all permission checks passed (main.typ + default.typ) ==="
