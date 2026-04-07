# Isolation

Shell tooling to provision **isolated Linux accounts** with a predictable **data layout** (shared datasets + per-user private trees), optional **collaborative shared software** (`~/shared_software`), a **default shell environment** (symlinks, templates, optional Miniconda), and optional **rootless Docker preparation** for a new user. The design is described in the Markdown docs under `doc/en/`.

## 1. Configuration

Defaults live in [`common/config.env`](common/config.env). Override for a single run with environment variables, for example:

```bash
sudo DATA_ROOT=/mnt/storage ./add-user.sh alice
```

## 2. Add user

Main entry point: [`add-user.sh`](add-user.sh).

```bash
sudo ./add-user.sh USERNAME [options]
```

`DATA_ROOT` comes from [`common/config.env`](common/config.env) (default `/data`) or override per run, e.g. `sudo DATA_ROOT=/mnt/storage ./add-user.sh alice`. It must be an **absolute** path.

**Examples**

```bash
sudo ./add-user.sh alice --password 'your-password'
```

```bash
sudo ./add-user.sh alice --password 'your-password' --install-miniconda
```

```bash
sudo ./add-user.sh frank --install-rootless-docker
```

**What it does (typical run)**

1. **Host layout** — [`isolation/init-host.sh`](isolation/init-host.sh): ensures `DATA_ROOT`, shared dataset directory (default `${DATA_ROOT}/shared_data`), and `shared_ro` group/mode per config.
2. **User** — [`isolation/add-isolation-user.sh`](isolation/add-isolation-user.sh): creates the account, home under `/home/<username>`, and private data at `${DATA_ROOT}/<username>_data` (suffix configurable via `USER_DATA_SUFFIX`; optional prefix via `USER_DATA_PREFIX`).
3. **Default environment** (unless `--no-default-user-env`) — initializes shared software layout ([`default-user-environment/init-shared-software-layout.sh`](default-user-environment/init-shared-software-layout.sh)) and applies env for that user ([`default-user-environment/apply-default-user-environment.sh`](default-user-environment/apply-default-user-environment.sh)):
   - **`~/shared_software`** → collaborative tree on the host (`SOFTWARE_ROOT`, default `${DATA_ROOT}/shared_software`) when enabled.
   - **`~/data`** → `DATA_ROOT` when `ENABLE_DATA_ROOT_LINK=1`, so shared and per-user `*_data` dirs are reachable from home.
   - **Templates** from `template/`: [`bashrc.sh`](template/bashrc.sh), [`zshrc.sh`](template/zshrc.sh), [`config.fish`](template/config.fish), [`vimrc`](template/vimrc) (behavior controlled by `--skip-templates`, `--force-templates`, etc.).

4. **Rootless Docker prep** (only with `--install-rootless-docker`) — [`docker/ubuntu/install-rootless-docker-for-user.sh`](docker/ubuntu/install-rootless-docker-for-user.sh); runs after user creation.

Optional flags:

- **`--install-miniconda`** — copies [`template/shell_utils`](template/shell_utils) to `~/shell_utils`, then runs [`install_miniconda.sh`](template/shell_utils/install_miniconda.sh) as the new user (so the install does not depend on reading the repo from another user’s home directory).
- **`--install-rootless-docker`** — runs [`docker/ubuntu/install-rootless-docker-for-user.sh`](docker/ubuntu/install-rootless-docker-for-user.sh) after the user exists (subuid/subgid checks, `loginctl enable-linger`, shell env snippets). The user still installs rootless Docker after login; see [`doc/en/docker.md`](doc/en/docker.md).

Run `sudo ./add-user.sh --help` for the full option list.


## 3. Fix migrated shared software

After **copying** a tree into `SOFTWARE_ROOT`, group ownership and directory **setgid** may not match the layout expected by [`doc/en/default.md`](doc/en/default.md). Use [`fix-migrated-shared-software.sh`](fix-migrated-shared-software.sh) to align paths under `SOFTWARE_ROOT` with `SOFTWARE_GROUP` (from `common/config.env`).

Each argument must **exist** and resolve to a path **under** `SOFTWARE_ROOT` (default `${DATA_ROOT}/shared_software`, often `/data/shared_software`). You can pass the tree root, one subtree, or several paths in one invocation.

```bash
# whole shared software tree (when SOFTWARE_ROOT is /data/shared_software)
sudo ./fix-migrated-shared-software.sh /data/shared_software

# one migrated package
sudo ./fix-migrated-shared-software.sh /data/shared_software/some-tool

# all immediate children (shell expands *; do not quote the glob)
sudo ./fix-migrated-shared-software.sh /data/shared_software/*
```

Permissions applied under each path (after `chgrp -R` to `SOFTWARE_GROUP` in all cases):

| Target                          | Default                                              | With `--normalize-perms`      |
| ------------------------------- | ---------------------------------------------------- | ----------------------------- |
| Directories                     | Add setgid: `chmod g+s` (other mode bits left as-is) | `2755` (setgid + `rwxr-xr-x`) |
| Regular files (no execute bit)  | Unchanged                                            | `644`                         |
| Regular files (any execute bit) | Unchanged                                            | `755`                         |

- Requires **`ENABLE_SOFTWARE_AREA=1`** in config.
- Use **`DRY_RUN=1`** to print planned actions only.

## 4. Remove user

[`remove-user.sh`](remove-user.sh) removes an account created by this flow. It does **not** tear down host-wide layout (shared data dir, shared software tree, or other users).

```bash
sudo ./remove-user.sh USERNAME [options]
```

`DATA_ROOT` must match the value used when the user was added (set the same way as for `add-user.sh`). Options are passed to [`isolation/remove-isolation-user.sh`](isolation/remove-isolation-user.sh) (`--keep-home`, `--keep-user-data`, `--dry-run`, `--force`, `--ignore-missing`, …). 

Run `sudo ./remove-user.sh --help` for detailed options.

## 5. Docker smoke test

Requires Docker. Runs the repo checks inside a container (default image `ubuntu:24.04`).

```bash
bash tests/docker-verify.sh --no-install-miniconda
```

Pass a different image as the first argument if it is not an option flag, for example `bash tests/docker-verify.sh debian:bookworm --no-install-miniconda`. Use `--install-miniconda` or set `INSTALL_MINICONDA=1` (default) to exercise the Miniconda path (needs network in the container).

## 6. Design reference

- [`doc/en/add-user.md`](doc/en/add-user.md) — account and directory isolation
- [`doc/en/default.md`](doc/en/default.md) — collaborative software directory, `~/data` → `DATA_ROOT`, templates, optional Miniconda
- [`doc/en/docker.md`](doc/en/docker.md) — rootless Docker preparation and post-login install

Host install helpers for Docker on Ubuntu live under [`docker/ubuntu/`](docker/ubuntu/) (apt repo, optional root daemon disable, per-user prep script).
