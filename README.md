# Isolation

Chinese documentation: [doc/zh/README.md](doc/zh/README.md).

- [Isolation](#isolation)
  - [1. What it does](#1-what-it-does)
  - [2. What it does not do](#2-what-it-does-not-do)
  - [3. Repository layout](#3-repository-layout)
  - [4. Prerequisites](#4-prerequisites)
  - [5. Quick start](#5-quick-start)
  - [6. Usage (`main.sh`)](#6-usage-mainsh)
  - [7. Configuration](#7-configuration)
    - [7.1. `isolation/isolation.env`](#71-isolationisolationenv)
    - [7.2. `default-user-environment/config.env`](#72-default-user-environmentconfigenv)
  - [8. Shell startup and `umask`](#8-shell-startup-and-umask)
  - [9. Docker smoke test](#9-docker-smoke-test)
  - [10. Known limits and operational notes](#10-known-limits-and-operational-notes)
  - [11. Design reference](#11-design-reference)

---

Lightweight isolation scripts for shared Linux research servers: one entry point, **`main.sh`**, provisions host layout, an isolated user, and (by default) the collaborative software tree and per-user defaults described in [doc/en/main.typ](doc/en/main.typ) and [doc/en/default.typ](doc/en/default.typ).

It is intentionally simple and does not try to be a full multi-tenant platform.

## 1. What it does

- **`/data` layout**: mount point `755`, shared datasets under `/data/shared` (group `shared_ro`, default mode `2775` per [doc/en/main.typ](doc/en/main.typ))
- **Per user**: home and `/data/<username>_data` at mode `700`, optional `shared_ro` membership
- **By default** (same run as above): `/data/shared_software` at `3775`, `software` group, `~/software` symlink, optional files from `template/` (`bashrc.sh`, `zshrc.sh`, `config.fish`, `vimrc` / `vimrc.sh`, optional `install_miniconda.sh`; existing files are appended once with a marked template block unless you choose skip/force behavior)
- **Dry run**: `DRY_RUN=1` or `main.sh --dry-run`

Skip the default-environment steps with `main.sh --no-default-user-env` if you only want the main.typ layout.

## 2. What it does not do

- No CPU, memory, or process limits (no cgroup/quota integration)
- No container isolation (not Docker/LXC based)
- No automatic hardening for SSHD, PAM, or auditing policies

If you need stronger isolation or resource control, add those mechanisms separately.

## 3. Repository layout

```text
.
├── main.sh                              # entry point (sudo ./main.sh USER DATA_ROOT …)
├── isolation/                           # host + user provisioning (used by main.sh)
├── default-user-environment/            # shared software + user defaults (used by main.sh)
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
sudo ./main.sh alice /data
```

This initializes `/data` and `/data/shared`, creates `alice` with `/data/alice_data`, and applies the default shared-software environment unless you add `--no-default-user-env`.

## 6. Usage (`main.sh`)

```bash
sudo ./main.sh USERNAME DATA_DIR [options]
```

`DATA_DIR` must be an absolute path (for example `/data`); it becomes `DATA_ROOT` for that run.

Options:

- `--join-shared-ro` / `--no-join-shared-ro`: add user to `shared_ro` (default: join)
- `--uid UID`, `--shell PATH`
- `--dry-run`: print actions only
- `--no-default-user-env`: skip shared-software init and template / `~/software` steps
- `--with-default-user-env`: explicit default (same as omitting the flag above)
- `--no-join-software`, `--skip-templates`, `--force-templates`, `--skip-existing-templates`, `--install-miniconda`: only relevant when default user env runs
- Template behavior when files already exist:
  - default: append template content once (idempotent via block markers)
  - `--skip-existing-templates`: keep existing files unchanged
  - `--force-templates`: overwrite destination files from `template/`

Examples:

```bash
sudo ./main.sh bob /mnt/research-data --no-join-shared-ro
sudo ./main.sh carol /data --uid 2301 --shell /bin/zsh
sudo ./main.sh dave /data --dry-run
sudo ./main.sh erin /data --no-default-user-env
sudo ./main.sh frank /data --install-miniconda
```

## 7. Configuration

Override defaults with environment variables; use `sudo -E ./main.sh …` if you exported them in your shell.

### 7.1. `isolation/isolation.env`

- `DATA_ROOT` (default `/data` — usually set by `main.sh` via `DATA_DIR`)
- `SHARED_GROUP`, `SHARED_MODE` (defaults `shared_ro`, `2775`)
- `DEFAULT_LOGIN_SHELL`, `USER_DATA_PREFIX`, `USER_DATA_SUFFIX` (`_data`)
- `USER_UMASK_HINT`, `DRY_RUN`, `ISOLATION_BASHRC_MARK`

### 7.2. `default-user-environment/config.env`

Loaded when the default-user-env phase runs; extends `isolation.env` with:

- `SOFTWARE_ROOT`, `SOFTWARE_GROUP`, `SOFTWARE_MODE` (`3775`)
- `USER_SOFTWARE_LINK_NAME` (`software`)
- `TEMPLATE_DIR` (repo `template/` by default)
- `ENABLE_SOFTWARE_AREA` (`1`; set `0` to disable that phase)

## 8. Shell startup and `umask`

For the chosen login shell, `main.sh`’s user-creation step may append a one-time `umask` hint. When the default environment runs, the same marker can be appended to existing `~/.bashrc`, `~/.zshrc`, and `~/.config/fish/config.fish` after any template copies.

## 9. Docker smoke test

```bash
./tests/docker-verify.sh
```

End-to-end permission checks inside a container (default image `ubuntu:24.04`; pull if missing). Optional: `./tests/docker-verify.sh OTHER_IMAGE` or set `USER_A` / `USER_B` / `USER_C`.

## 10. Known limits and operational notes

- Isolation is permission-based (UID/GID + modes), not a sandbox
- Root can access all data by design
- Tighter sharing: e.g. `SHARED_MODE=0750` via env before `main.sh`
- New supplementary groups need a new session (`newgrp` or re-login) before `id` shows them

## 11. Design reference

- [doc/en/main.typ](doc/en/main.typ) — account and directory isolation
- [doc/en/default.typ](doc/en/default.typ) — collaborative software directory, templates, optional Miniconda
