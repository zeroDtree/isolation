# Isolation

Shell tooling to provision **isolated Linux accounts** with a predictable **data layout** (shared datasets + per-user private trees), optional **collaborative shared software** (`~/shared_software`), and a **default shell environment** (symlinks, templates, optional Miniconda). The design is described in the Markdown docs under `doc/en/`.

## 1. Configuration

Defaults live in [`common/config.env`](common/config.env). Override for a single run with environment variables, for example:

```bash
sudo DATA_ROOT=/mnt/storage ./add-user.sh alice /mnt/storage
```

## 2. Add user

Main entry point: [`add-user.sh`](add-user.sh).

```bash
sudo ./add-user.sh USERNAME DATA_DIR [options]
```

`DATA_DIR` must be an **absolute** path (for that invocation it is `DATA_ROOT`, e.g. `/data`).

**Example**

- 
  ```bash
  sudo ./add-user.sh alice /data --password 'your-password'
  ```
- 
  ```bash
  sudo ./add-user.sh alice /data --password 'your-password' --install-miniconda
  ```

**What it does (typical run)**

1. **Host layout** — [`isolation/init-host.sh`](isolation/init-host.sh): ensures `DATA_ROOT`, shared dataset directory (default `${DATA_ROOT}/shared_data`), and `shared_ro` group/mode per config.
2. **User** — [`isolation/add-isolation-user.sh`](isolation/add-isolation-user.sh): creates the account, home under `/home/<username>`, and private data at `${DATA_ROOT}/<username>_data` (suffix configurable via `USER_DATA_SUFFIX`; optional prefix via `USER_DATA_PREFIX`).
3. **Default environment** (unless `--no-default-user-env`) — initializes shared software layout ([`default-user-environment/init-shared-software-layout.sh`](default-user-environment/init-shared-software-layout.sh)) and applies env for that user ([`default-user-environment/apply-default-user-environment.sh`](default-user-environment/apply-default-user-environment.sh)):
   - **`~/shared_software`** → collaborative tree on the host (`SOFTWARE_ROOT`, default `${DATA_ROOT}/shared_software`) when enabled.
   - **`~/data`** → `DATA_ROOT` when `ENABLE_DATA_ROOT_LINK=1`, so shared and per-user `*_data` dirs are reachable from home.
   - **Templates** from `template/`: [`bashrc.sh`](template/bashrc.sh), [`zshrc.sh`](template/zshrc.sh), [`config.fish`](template/config.fish), [`vimrc`](template/vimrc) (behavior controlled by `--skip-templates`, `--force-templates`, etc.).

Optional: `--install-miniconda` runs [`default-user-environment/install_miniconda.sh`](default-user-environment/install_miniconda.sh) as the new user.

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
sudo ./remove-user.sh USERNAME DATA_DIR [options]
```

`DATA_DIR` must match the `DATA_ROOT` used when the user was added. Options are passed to [`isolation/remove-isolation-user.sh`](isolation/remove-isolation-user.sh) (`--keep-home`, `--keep-user-data`, `--dry-run`, `--force`, `--ignore-missing`, …). 

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
