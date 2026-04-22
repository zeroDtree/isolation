# Isolation

Shell tooling to provision **isolated Linux accounts**. It covers:

- **Data layout** — shared datasets plus per-user private trees under a configurable root.
- **Collaborative shared software** (optional) — e.g. default `~/shared_software` (configurable via `USER_SOFTWARE_LINK_NAME`) into a shared tree on the host.
- **Default shell environment** — symlinks such as default `~/data` (`USER_DATA_ROOT_LINK_NAME`) and optional `~/.cache` into private data, templates, and optional Miniconda.
- **Rootless Docker preparation** (optional) — host checks and user-facing setup hooks.

## 1. Configuration

Defaults live in [`common/config.env`](common/config.env). Override for a single run with environment variables, for example:

```bash
sudo DATA_ROOT=/path/to/data_root bash add-user.sh USERNAME
```

## 2. Add user

Main entry point: [`add-user.sh`](add-user.sh).

```bash
sudo DATA_ROOT=/path/to/data_root bash add-user.sh USERNAME [options]
```

`DATA_ROOT` comes from [`common/config.env`](common/config.env) (default `/data`) or override per run. It must be an **absolute** path.

If the **Linux user already exists**, [`add-user.sh`](add-user.sh) does not call [`isolation/add-isolation-user.sh`](isolation/add-isolation-user.sh); the rest of the run proceeds as usual (init host, then default environment and optional rootless Docker prep). Options meant only for user creation (for example `--password`) have no effect in that case.

**Examples**

```bash
sudo DATA_ROOT=/data bash add-user.sh alice --password 'your-password' --with-install-miniconda --with-install-rootless-docker
```

**What it does (typical run)**

1. **Host layout** — [`isolation/init-host.sh`](isolation/init-host.sh): ensures `DATA_ROOT`, shared dataset directory (default `${DATA_ROOT}/shared_data`), and `SHARED_GROUP` (default `shared_data`) plus mode per config.
2. **User** — [`isolation/add-isolation-user.sh`](isolation/add-isolation-user.sh): creates the account and home under `/home/<username>`. If the account already exists, this step is skipped and the script continues.
3. **Default environment** (unless `--no-default-user-env`) — runs shared software layout init ([`default-user-environment/init-shared-software-layout.sh`](default-user-environment/init-shared-software-layout.sh); no-op when `ENABLE_SOFTWARE_AREA` is not `1`) and applies env for that user ([`default-user-environment/apply-default-user-environment.sh`](default-user-environment/apply-default-user-environment.sh)):
   - **Shared-data group + private data dir** — add the user to `SHARED_GROUP` by default (use `--no-join-shared-data-group` to skip), and ensure the per-user private data directory `${DATA_ROOT}/<prefix><username><suffix>` exists with mode `USER_DATA_DIR_MODE`.
   - **`~/shared_software`** (default link name `USER_SOFTWARE_LINK_NAME`) → collaborative tree on the host (`SOFTWARE_ROOT`, default `${DATA_ROOT}/shared_software`) when **`ENABLE_SOFTWARE_AREA=1`** and you do not pass **`--no-join-shared-software-group`** (default is to join).
   - **`~/data`** (default link name `USER_DATA_ROOT_LINK_NAME`) → `DATA_ROOT` when **`ENABLE_DATA_ROOT_LINK=1`**, so shared and per-user `*_data` dirs are reachable from home.
   - **`~/.cache`** → a directory under the per-user private data tree (same `${DATA_ROOT}/<prefix><username><suffix>/…` rule as this step; backing basename `USER_CACHE_BACKING_NAME`, default `.cache`) when **`ENABLE_USER_CACHE_LINK=1`** and you do not pass **`--no-user-cache-link`** on `add-user.sh` (default is to create the symlink when both config and CLI allow it).
   - **Templates** from `template/`: [`bashrc.sh`](template/bashrc.sh), [`zshrc.sh`](template/zshrc.sh), [`config.fish`](template/config.fish), [`vimrc`](template/vimrc) (or `vimrc.sh` if present). Flags include **`--skip-templates`** / **`--with-templates`**, **`--force-templates`** / **`--no-force-templates`**, **`--skip-existing-templates`** / **`--no-skip-existing-templates`**.

4. **Rootless Docker prep** (only with **`--with-install-rootless-docker`**) — runs [`docker/ubuntu/install-rootless-docker-for-user.sh`](docker/ubuntu/install-rootless-docker-for-user.sh) after the user step. Use **`--no-install-rootless-docker`** to skip explicitly.

Optional flags (see `sudo ./add-user.sh --help` for the full list):

## 3. Fix migrated shared software

After **copying** a tree into `SOFTWARE_ROOT`, group ownership and directory **setgid** may not match the collaborative layout this tooling expects. Use [`fix-migrated-shared-software.sh`](fix-migrated-shared-software.sh) to align paths under `SOFTWARE_ROOT` with `SOFTWARE_GROUP` (from `common/config.env`).

Each argument must **exist** and resolve to a path **under** `SOFTWARE_ROOT` (default `${DATA_ROOT}/shared_software`, often `/data/shared_software`). You can pass the tree root, one subtree, or several paths in one invocation.

```bash
# all immediate children (shell expands *; do not quote the glob)
sudo DATA_ROOT=/path/to/data_root bash fix-migrated-shared-software.sh /path/to/data_root/shared_software/* --normalize-perms
```

Permissions applied under each path (after `chgrp -R` to `SOFTWARE_GROUP` in all cases):

| Target                          | Default                                              | With `--normalize-perms`      |
| ------------------------------- | ---------------------------------------------------- | ----------------------------- |
| Directories                     | Add setgid: `chmod g+s` (other mode bits left as-is) | `2755` (setgid + `rwxr-xr-x`) |
| Regular files (no execute bit)  | Unchanged                                            | `644`                         |
| Regular files (any execute bit) | Unchanged                                            | `755`                         |

- Requires **`ENABLE_SOFTWARE_AREA=1`** in config.
- Use **`DRY_RUN=1`** to print planned actions only.

## 4. Fix migrated shared data

After **copying** a tree into `SHARED_DATA_PATH`, group ownership and directory **setgid** may not match the shared-data layout this tooling expects. Use [`fix-migrated-shared-data.sh`](fix-migrated-shared-data.sh) to align paths under `SHARED_DATA_PATH` with `SHARED_GROUP` (from `common/config.env`).

Each argument must **exist** and resolve to a path **under** `SHARED_DATA_PATH` (default `${DATA_ROOT}/shared_data`, often `/data/shared_data`). You can pass the tree root, one subtree, or several paths in one invocation.

```bash
# all immediate children (shell expands *; do not quote the glob)
sudo DATA_ROOT=/path/to/data_root bash fix-migrated-shared-data.sh /path/to/data_root/shared_data/* --normalize-perms
```

Permissions applied under each path (after `chgrp -R` to `SHARED_GROUP` in all cases):

| Target                          | Default                                              | With `--normalize-perms`      |
| ------------------------------- | ---------------------------------------------------- | ----------------------------- |
| Directories                     | Add setgid: `chmod g+s` (other mode bits left as-is) | `2755` (setgid + `rwxr-xr-x`) |
| Regular files (no execute bit)  | Unchanged                                            | `644`                         |
| Regular files (any execute bit) | Unchanged                                            | `755`                         |

- Ensure **`SHARED_DATA_PATH`** exists (`isolation/init-host.sh` creates it).
- Use **`DRY_RUN=1`** to print planned actions only.

## 5. Remove user

[`remove-user.sh`](remove-user.sh) removes an account created by this flow. It does **not** tear down host-wide layout (shared data dir, shared software tree, or other users).

```bash
sudo DATA_ROOT=/path/to/data_root bash remove-user.sh USERNAME
```

`DATA_ROOT` must match the value used when the user was added (set the same way as for `add-user.sh`). Options are passed to [`isolation/remove-isolation-user.sh`](isolation/remove-isolation-user.sh) (`--keep-home`, `--keep-user-data`, `--dry-run`, `--force`, `--ignore-missing`, …).

Run `sudo ./remove-user.sh --help` for detailed options.

## 6. Docker smoke test

Requires Docker. Runs the repo checks inside a container (default image `ubuntu:24.04`).

```bash
bash tests/docker-verify.sh --no-install-miniconda
```

[`tests/docker-verify.sh`](tests/docker-verify.sh) is **not** `add-user.sh`: it accepts **`--no-install-miniconda`** and **`--with-install-miniconda`** only on this wrapper (same naming as `add-user.sh`), and exports **`INSTALL_MINICONDA`** for [`tests/docker-verify-inner.sh`](tests/docker-verify-inner.sh) (default `1`, so the inner script runs `add-user.sh … --with-install-miniconda` unless you skip). The **container image** is the optional **first** argument (default `ubuntu:24.04` if omitted), same style as **`USERNAME [options]`** elsewhere; put Miniconda flags **after** the image, for example `bash tests/docker-verify.sh debian:bookworm --no-install-miniconda`. You can also set **`INSTALL_MINICONDA=0`** in the environment instead of **`--no-install-miniconda`**. The Miniconda path needs network in the container.
