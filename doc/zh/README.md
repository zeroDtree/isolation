# Isolation（中文说明）

英文版请见仓库根目录 [README.md](../../README.md)。

- [Isolation（中文说明）](#isolation中文说明)
  - [1. 本仓库做什么](#1-本仓库做什么)
  - [2. 本仓库不做什么](#2-本仓库不做什么)
  - [3. 仓库结构](#3-仓库结构)
  - [4. 前置条件](#4-前置条件)
  - [5. 快速开始](#5-快速开始)
  - [6. 用法（add-user.sh）](#6-用法add-usersh)
    - [6.1. 删除用户](#61-删除用户)
  - [7. 配置](#7-配置)
    - [7.1. `isolation/isolation.env`](#71-isolationisolationenv)
    - [7.2. `default-user-environment/config.env`](#72-default-user-environmentconfigenv)
  - [8. Shell 启动与 `umask`](#8-shell-启动与-umask)
  - [9. Docker 冒烟测试](#9-docker-冒烟测试)
  - [10. 已知限制与运维说明](#10-已知限制与运维说明)
  - [11. 设计文档索引](#11-设计文档索引)

---

面向共享 Linux 科研服务器的轻量隔离脚本：单一入口 **`add-user.sh`** 负责初始化主机目录、隔离用户，并在默认情况下按 [main.typ](main.typ) 与 [default.typ](default.typ) 所述配置协作软件树与每用户默认环境。

刻意保持简单，不追求完整多租户平台。

## 1. 本仓库做什么

- **`/data` 布局**：挂载点 `755`，共享数据集在 `${DATA_ROOT}/${SHARED_DATA_DIR_NAME}`（默认 `/data/shared_data`，组 `shared_ro`，默认模式 `3775`，见 [main.typ](main.typ)）
- **每用户**：主目录与 `/data/<用户名>_data` 为 `700`，可选加入 `shared_ro`
- **默认**（同一次运行）：`/data/shared_software` 为 `3775`、`software` 组、`~/shared_software` 符号链接，`~/data`（名称可配）指向 `DATA_ROOT` 的符号链接（便于找到共享数据集与 `*_data` 等，无需记宿主机路径），以及来自 `template/` 的可选文件（`bashrc.sh`、`zshrc.sh`、`config.fish`、`vimrc` / `vimrc.sh`、可选 `install_miniconda.sh`）；当目标文件已存在时，默认以“带标记的模板块”追加一次（幂等），也可改为跳过或覆盖
- **演练**：`DRY_RUN=1` 或 `add-user.sh --dry-run`

若只需要 main.typ 中的目录布局、不需要默认环境步骤，可使用 `add-user.sh --no-default-user-env`。

## 2. 本仓库不做什么

- 不做 CPU、内存或进程数限制（未集成 cgroup/配额）
- 不做容器级隔离（非 Docker/LXC 方案）
- 不自动加固 sshd、PAM 或审计策略

若需要更强隔离或资源控制，请另行叠加相应机制。

## 3. 仓库结构

```text
.
├── add-user.sh                              # 入口（sudo ./add-user.sh 用户 数据根 …）
├── remove-user.sh                       # 删除用户、主目录与 DATA_ROOT 下对应 *_data（见 isolation/remove-isolation-user.sh）
├── fix-migrated-shared-software.sh      # 可选：拷贝后修正组与目录权限（--normalize-perms 为 2755/644/755）
├── isolation/                           # 主机与用户开通（由 add-user.sh 调用）
├── default-user-environment/            # 共享软件与用户默认（由 add-user.sh 调用）
├── template/                            # 可选：为新用户复制或执行的文件
├── tests/                               # ./tests/docker-verify.sh — 可选冒烟测试
└── doc/
    ├── en/
    │   ├── main.typ
    │   └── default.typ
    └── zh/
        ├── README.md
        ├── main.typ
        └── default.typ
```

## 4. 前置条件

- Linux 主机
- root 权限（`sudo`）
- `bash`、`useradd`、`usermod`、`groupadd`

## 5. 快速开始

```bash
sudo ./add-user.sh alice /data
```

将初始化 `/data` 与共享数据目录（默认 `/data/shared_data`），创建用户 `alice` 及其 `/data/alice_data`，并应用默认共享软件环境（含 `~/shared_software` 与 `~/data` → `DATA_ROOT`，除非加上 `--no-default-user-env`）。

## 6. 用法（add-user.sh）

```bash
sudo ./add-user.sh 用户名 数据目录 [选项…]
```

`数据目录` 须为绝对路径（例如 `/data`）；本次运行中作为 `DATA_ROOT`。

选项：

- `--join-shared-ro` / `--no-join-shared-ro`：是否将用户加入 `shared_ro`（默认：加入）
- `--uid UID`、`--password PASS`、`--shell PATH`
- `--dry-run`：仅打印将要执行的操作
- `--no-default-user-env`：跳过共享软件初始化、模板与 `~/shared_software`、`~/data` → `DATA_ROOT` 相关步骤
- `--with-default-user-env`：显式启用默认环境（与省略上述「关闭」类标志相同）
- `--no-join-software`、`--skip-templates`、`--force-templates`、`--skip-existing-templates`、`--install-miniconda`：仅在默认用户环境阶段生效
- 模板文件已存在时的行为：
  - 默认：追加模板内容一次（通过标记实现幂等）
  - `--skip-existing-templates`：保持已有文件不变
  - `--force-templates`：用 `template/` 中的文件覆盖目标文件

示例：

```bash
sudo ./add-user.sh bob /mnt/research-data --no-join-shared-ro
sudo ./add-user.sh alice /data --password 'S3cret!'
sudo ./add-user.sh carol /data --uid 2301 --shell /bin/zsh
sudo ./add-user.sh dave /data --dry-run
sudo ./add-user.sh erin /data --no-default-user-env
sudo ./add-user.sh frank /data --install-miniconda
```

### 6.1. 删除用户

```bash
sudo ./remove-user.sh 用户名 数据目录 [选项…]
```

`数据目录` 须与创建该用户时传给 `add-user.sh` 的 `DATA_ROOT` 一致（例如 `/data`）。默认使用 `userdel -r` 删除账号、主目录与邮件池，并删除 `/data/<用户名>_data`（或 `isolation.env` 中 `USER_DATA_PREFIX` / `USER_DATA_SUFFIX` 所定路径）。**不会**删除共享数据目录（默认 `/data/shared_data`）、`/data/shared_software` 或其他用户数据。选项：`--dry-run`、`--keep-home`、`--keep-user-data`、`--force`（在支持的环境下为 `userdel -f`）、`--ignore-missing`（账号已不存在时不报错；仍可删除遗留的 `*_data` 目录）。

## 7. 配置

可用环境变量覆盖默认值；若在当前 shell 中已 export，请使用 `sudo -E ./add-user.sh …`。

### 7.1. `isolation/isolation.env`

- `DATA_ROOT`（默认 `/data`——通常由 `add-user.sh` 通过 `数据目录` 传入）
- `SHARED_DATA_DIR_NAME`（默认 `shared_data`）、`SHARED_DATA_PATH`（默认 `${DATA_ROOT}/${SHARED_DATA_DIR_NAME}`）、`SHARED_GROUP`、`SHARED_DATA_MODE`（默认 `shared_ro`、`3775`）
- `DEFAULT_LOGIN_SHELL`、`USER_DATA_PREFIX`、`USER_DATA_SUFFIX`（`_data`）
- `USER_UMASK_HINT`、`DRY_RUN`、`ISOLATION_BASHRC_MARK`

### 7.2. `default-user-environment/config.env`

在默认用户环境阶段加载；在 `isolation.env` 基础上扩展：

- `SOFTWARE_ROOT`、`SOFTWARE_GROUP`、`SHARED_SOFTWARE_MODE`（`3775`）
- `USER_SOFTWARE_LINK_NAME`（`shared_software`）
- `USER_DATA_ROOT_LINK_NAME`（`data`）：家目录下 `~/<名称>` → `DATA_ROOT` 的链接名
- `ENABLE_DATA_ROOT_LINK`（`1`；设为 `0` 可跳过该符号链接）
- `TEMPLATE_DIR`（默认同仓库 `template/`）
- `ENABLE_SOFTWARE_AREA`（`1`；设为 `0` 可关闭该阶段）

## 8. Shell 启动与 `umask`

对所选登录 shell，`add-user.sh` 创建用户时可能会追加一次性 `umask` 提示。默认环境运行时，也会在 `~/.bashrc`、`~/.zshrc`、`~/.config/fish/config.fish` 中按标记追加相同提示（只追加一次）。

## 9. Docker 冒烟测试

```bash
./tests/docker-verify.sh
```

在容器内做端到端权限检查（默认镜像 `ubuntu:24.04`；若本地无则拉取）。可选：`./tests/docker-verify.sh 其他镜像` 或设置环境变量 `USER_A` / `USER_B` / `USER_C`。测试里安装 Miniconda 需要镜像内有 `wget` 或 `curl`；可用 `INSTALL_MINICONDA=0 ./tests/docker-verify.sh` 或 `./tests/docker-verify.sh --no-install-miniconda` 跳过。

## 10. 已知限制与运维说明

- 将软件树拷贝进 `SOFTWARE_ROOT` 后，可执行 `sudo ./fix-migrated-shared-software.sh /data/shared_software/你的目录`，统一属组为 `SOFTWARE_GROUP` 并为子目录设置 setgid（见 [default.typ](default.typ)）；需要批量规范化权限时可加 `--normalize-perms`（目录 `2755`、非可执行 `644`、原先可执行再 `755`）；支持 `DRY_RUN=1`。
- 若单独执行 `default-user-environment/apply-default-user-environment.sh`，请将 `DATA_ROOT` 设为开通该用户时使用的数据根（例如 `sudo DATA_ROOT=/mnt/research-data ./default-user-environment/apply-default-user-environment.sh alice`）；`add-user.sh` 会自动传入。
- 隔离基于权限（UID/GID + 模式），不是沙箱
- root 按设计可访问全部数据
- 更严格的共享：可在运行 `add-user.sh` 前通过环境变量设置，例如 `SHARED_DATA_MODE=0750`
- 新增附属组后需新会话（`newgrp` 或重新登录）后 `id` 才会显示

## 11. 设计文档索引

- [main.typ](main.typ) — 账户与目录隔离
- [default.typ](default.typ) — 协作软件目录、`~/data` → `DATA_ROOT`、模板、可选 Miniconda

英文设计说明源文件：[doc/en/main.typ](../en/main.typ)、[doc/en/default.typ](../en/default.typ)。
