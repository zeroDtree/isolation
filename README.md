# Isolation

Lightweight isolation scripts for shared Linux research servers.

This repository focuses on practical account-and-permission isolation:

1. Initialize host data layout (for example `/data` and `/data/shared`)
2. Create isolated users with private data directories (default `/data/<username>_data`)

It is intentionally simple and does not try to be a full multi-tenant platform.

## What it does

- Initializes host-side layout with `scripts/init-host.sh`
- Creates users with `scripts/add-isolation-user.sh`, including:
  - Login shell setup
  - Home directory permission `700`
  - Private data directory permission `700`
  - Optional shared group membership (`shared_ro`, enabled by default)
- Runs both steps in one command via `main.sh`
- Supports dry run mode via `DRY_RUN=1` or `--dry-run`

## What it does not do

- No CPU, memory, or process limits (no cgroup/quota integration)
- No container isolation (not Docker/LXC based)
- No automatic hardening for SSHD, PAM, or auditing policies

If you need stronger isolation or resource control, add those mechanisms separately.

## Repository layout

```text
.
├── main.sh                         # One-shot entry: init + user creation
├── scripts/
│   ├── isolation.env               # Default config values (overridable)
│   ├── isolation-common.sh         # Shared helper functions
│   ├── init-host.sh                # Initialize /data and /data/shared
│   └── add-isolation-user.sh       # Create one isolated user
└── doc/main.typ                    # Design notes and permission model
```

## Prerequisites

- Linux host
- Root privileges (scripts enforce this; use `sudo`)
- Core system tools such as `bash`, `useradd`, `usermod`, `groupadd`

## Quick start

### One-shot setup (recommended)

```bash
sudo ./main.sh alice /data
```

This performs:

- Host layout initialization at `/data` and `/data/shared`
- User creation for `alice`
- Private data directory creation at `/data/alice_data` (default naming)

### Step-by-step setup

```bash
# Step 1: initialize host directories and shared group
sudo DATA_ROOT=/data ./scripts/init-host.sh

# Step 2: create one isolated user
sudo DATA_ROOT=/data ./scripts/add-isolation-user.sh alice
```

## `main.sh` usage

```bash
sudo ./main.sh USERNAME DATA_DIR [options]
```

Options:

- `--join-shared-ro`: add user to shared group (default)
- `--no-join-shared-ro`: do not add user to shared group
- `--uid UID`: set explicit UID
- `--shell PATH`: set login shell
- `--dry-run`: print commands only, do not execute

Examples:

```bash
sudo ./main.sh bob /mnt/research-data --no-join-shared-ro
sudo ./main.sh carol /data --uid 2301 --shell /bin/zsh
sudo ./main.sh dave /data --dry-run
```

## Configuration (`scripts/isolation.env`)

Defaults can be overridden via environment variables.

- `DATA_ROOT` (default: `/data`)
- `SHARED_GROUP` (default: `shared_ro`)
- `SHARED_MODE` (default: `2775`)
- `DEFAULT_LOGIN_SHELL` (default: `/bin/bash`)
- `USER_DATA_PREFIX` (default: empty)
- `USER_DATA_SUFFIX` (default: `_data`)
- `USER_UMASK_HINT` (default: `027`)
- `DRY_RUN` (default: `0`)
- `ISOLATION_BASHRC_MARK` (default marker text for one-time append check)

Examples:

```bash
sudo DATA_ROOT=/srv/data SHARED_MODE=0750 ./scripts/init-host.sh
sudo DATA_ROOT=/srv/data USER_DATA_SUFFIX=_workspace ./scripts/add-isolation-user.sh erin
```

## Shell startup file behavior for `umask`

When creating a user, the script appends a one-time `umask` hint block only if the marker is missing:

- Bash users: `~/.bashrc`
- Zsh users: `~/.zshrc`
- Fish users: `~/.config/fish/config.fish`

In dry-run mode, it only prints what would be appended.

## Verification checklist

After user creation, verify:

- `ls -ld /data /data/shared /data/<user>_data`
- `id <user>` to confirm `shared_ro` membership policy
- Access checks from another non-root account:
  - `<user>` home directory should be inaccessible
  - `<user>` private data directory should be inaccessible

## Known limits and operational notes

- Isolation is permission-based (UID/GID + file modes), not sandbox/container based
- Root can access all user data by design
- `SHARED_MODE=2775` allows group collaboration writes; for stricter read-only sharing, use tighter modes such as `0750` and control group write paths separately

## Design reference

For background and rationale, see [doc/main.typ](doc/main.typ).
