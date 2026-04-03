# Isolation

Chinese documentation: [doc/zh/README.md](doc/zh/README.md).

- [Isolation](#isolation)
  - [1. What it does](#1-what-it-does)
  - [2. What it does not do](#2-what-it-does-not-do)
  - [3. Repository layout](#3-repository-layout)
  - [4. Prerequisites](#4-prerequisites)
  - [5. Quick start](#5-quick-start)
  - [6. Usage (`add-user.sh`)](#6-usage-add-usersh)
    - [6.1. Remove a user](#61-remove-a-user)
  - [7. Configuration](#7-configuration)
    - [7.1. `isolation/isolation.env`](#71-isolationisolationenv)
    - [7.2. `default-user-environment/config.env`](#72-default-user-environmentconfigenv)
  - [8. Shell startup and `umask`](#8-shell-startup-and-umask)
  - [9. Docker smoke test](#9-docker-smoke-test)
  - [10. Known limits and operational notes](#10-known-limits-and-operational-notes)
  - [11. Design reference](#11-design-reference)

---

Lightweight isolation scripts for shared Linux research servers: one entry point, **`add-user.sh`**, provisions host layout, an isolated user, and (by default) the collaborative software tree and per-user defaults described in [doc/en/main.typ](doc/en/main.typ) and [doc/en/default.typ](doc/en/default.typ).

It is intentionally simple and does not try to be a full multi-tenant platform.

## 1. What it does

- **`/data` layout**: mount point `755`, shared datasets under `${DATA_ROOT}/${SHARED_DATA_DIR_NAME}` (default `/data/shared_data`, group `shared_ro`, default mode `3775` per [doc/en/main.typ](doc/en/main.typ))
- **Per user**: home and `/data/<username>_data` at mode `700`, optional `shared_ro` membership
- **By default** (same run as above): `/data/shared_software` at `3775`, `software` group, `~/shared_software` symlink, a `~/data` symlink (name configurable) pointing at `DATA_ROOT` so users can open shared datasets and `*_data` trees without memorizing the host path, optional files from `template/` (`bashrc.sh`, `zshrc.sh`, `config.fish`, `vimrc` / `vimrc.sh`, optional `install_miniconda.sh`; existing files are appended once with a marked template block unless you choose skip/force behavior)
- **Dry run**: `DRY_RUN=1` or `add-user.sh --dry-run`

Skip the default-environment steps with `add-user.sh --no-default-user-env` if you only want the main.typ layout.

## 2. What it does not do

- No CPU, memory, or process limits (no cgroup/quota integration)
- No container isolation (not Docker/LXC based)
- No automatic hardening for SSHD, PAM, or auditing policies

If you need stronger isolation or resource control, add those mechanisms separately.

## 3. Repository layout

```text
.
├── add-user.sh                              # entry point (sudo ./add-user.sh USER DATA_ROOT …)
├── remove-user.sh                       # remove user + home + DATA_ROOT/<user>_data (see isolation/remove-isolation-user.sh)
├── fix-migrated-shared-software.sh      # optional: chgrp + dir perms after copy (--normalize-perms for 2755/644/755)
├── isolation/                           # host + user provisioning (used by add-user.sh)
├── default-user-environment/            # shared software + user defaults (used by add-user.sh)
├── template/                            # optional files copied or executed for new users
├── tests/                               # ./tests/docker-verify.sh — optional smoke test
└── doc/
    ├── en/
    │   ├── main.typ
    │   └── default.typ
    └── zh/
        ├── README.md
        ├── main.typ
        └── default.typ
```

## 4. Prerequisites

- Linux host
- Root privileges (`sudo`)
- `bash`, `useradd`, `usermod`, `groupadd`

## 5. Quick start

```bash
sudo ./add-user.sh alice /data
```

This initializes `/data` and the shared data directory (default `/data/shared_data`), creates `alice` with `/data/alice_data`, and applies the default shared-software environment (including `~/shared_software` and `~/data` → `DATA_ROOT`) unless you add `--no-default-user-env`.

## 6. Usage (`add-user.sh`)

```bash
sudo ./add-user.sh USERNAME DATA_DIR [options]
```

`DATA_DIR` must be an absolute path (for example `/data`); it becomes `DATA_ROOT` for that run.

Options:

- `--join-shared-ro` / `--no-join-shared-ro`: add user to `shared_ro` (default: join)
- `--uid UID`, `--password PASS`, `--shell PATH`
- `--dry-run`: print actions only
- `--no-default-user-env`: skip shared-software init and template / `~/shared_software` / `~/data` → `DATA_ROOT` steps
- `--with-default-user-env`: explicit default (same as omitting the flag above)
- `--no-join-software`, `--skip-templates`, `--force-templates`, `--skip-existing-templates`, `--install-miniconda`: only relevant when default user env runs
- Template behavior when files already exist:
  - default: append template content once (idempotent via block markers)
  - `--skip-existing-templates`: keep existing files unchanged
  - `--force-templates`: overwrite destination files from `template/`

Examples:

```bash
sudo ./add-user.sh bob /mnt/research-data --no-join-shared-ro
sudo ./add-user.sh alice /data --password 'S3cret!'
sudo ./add-user.sh carol /data --uid 2301 --shell /bin/zsh
sudo ./add-user.sh dave /data --dry-run
sudo ./add-user.sh erin /data --no-default-user-env
sudo ./add-user.sh frank /data --install-miniconda
```

### 6.1. Remove a user

```bash
sudo ./remove-user.sh USERNAME DATA_DIR [options]
```

`DATA_DIR` must match the `DATA_ROOT` used when the user was created (for example `/data`). By default this removes the account with `userdel -r` (home and mail spool) and deletes `/data/<username>_data` (or the configured `USER_DATA_PREFIX` / `USER_DATA_SUFFIX`). It does **not** remove the shared data directory (default `/data/shared_data`), `/data/shared_software`, or other users. Options: `--dry-run`, `--keep-home`, `--keep-user-data`, `--force` (passes `userdel -f` where supported), `--ignore-missing` (no error if the account is already gone; can still drop the data dir).

## 7. Configuration

Override defaults with environment variables; use `sudo -E ./add-user.sh …` if you exported them in your shell.

### 7.1. `isolation/isolation.env`

- `DATA_ROOT` (default `/data` — usually set by `add-user.sh` via `DATA_DIR`)
- `SHARED_DATA_DIR_NAME` (default `shared_data`), `SHARED_DATA_PATH` (default `${DATA_ROOT}/${SHARED_DATA_DIR_NAME}`), `SHARED_GROUP`, `SHARED_DATA_MODE` (defaults `shared_ro`, `3775`)
- `DEFAULT_LOGIN_SHELL`, `USER_DATA_PREFIX`, `USER_DATA_SUFFIX` (`_data`)
- `USER_UMASK_HINT`, `DRY_RUN`, `ISOLATION_BASHRC_MARK`

### 7.2. `default-user-environment/config.env`

Loaded when the default-user-env phase runs; extends `isolation.env` with:

- `SOFTWARE_ROOT`, `SOFTWARE_GROUP`, `SHARED_SOFTWARE_MODE` (`3775`)
- `USER_SOFTWARE_LINK_NAME` (`shared_software`)
- `USER_DATA_ROOT_LINK_NAME` (`data`): basename of `~/<name>` → `DATA_ROOT`
- `ENABLE_DATA_ROOT_LINK` (`1`; set `0` to skip that symlink)
- `TEMPLATE_DIR` (repo `template/` by default)
- `ENABLE_SOFTWARE_AREA` (`1`; set `0` to disable that phase)

## 8. Shell startup and `umask`

For the chosen login shell, `add-user.sh`’s user-creation step may append a one-time `umask` hint. When the default environment runs, the same marker can be appended to existing `~/.bashrc`, `~/.zshrc`, and `~/.config/fish/config.fish` after any template copies.

## 9. Docker smoke test

```bash
./tests/docker-verify.sh
```

End-to-end permission checks inside a container (default image `ubuntu:24.04`; pull if missing). Optional: `./tests/docker-verify.sh OTHER_IMAGE` or set `USER_A` / `USER_B` / `USER_C`. Miniconda in the test needs `wget` or `curl` in the image; skip it with `INSTALL_MINICONDA=0 ./tests/docker-verify.sh` or `./tests/docker-verify.sh --no-install-miniconda`.

## 10. Known limits and operational notes

- After copying a tree into `SOFTWARE_ROOT`, run `sudo ./fix-migrated-shared-software.sh /data/shared_software/yourtree` so the subtree uses `SOFTWARE_GROUP` and directory setgid (see [doc/en/default.typ](doc/en/default.typ)); add `--normalize-perms` for dirs `2755`, non-executables `644`, then prior executables `755`; `DRY_RUN=1` is supported.
- If you run `default-user-environment/apply-default-user-environment.sh` by hand, set `DATA_ROOT` to the same path used when the account was created (for example `sudo DATA_ROOT=/mnt/research-data ./default-user-environment/apply-default-user-environment.sh alice`); `add-user.sh` passes this automatically.
- Isolation is permission-based (UID/GID + modes), not a sandbox
- Root can access all data by design
- Tighter sharing: e.g. `SHARED_DATA_MODE=0750` via env before `add-user.sh`
- New supplementary groups need a new session (`newgrp` or re-login) before `id` shows them

## 11. Design reference

- [doc/en/main.typ](doc/en/main.typ) — account and directory isolation
- [doc/en/default.typ](doc/en/default.typ) — collaborative software directory, `~/data` → `DATA_ROOT`, templates, optional Miniconda
