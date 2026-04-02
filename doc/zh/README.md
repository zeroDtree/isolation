# Isolation（中文说明）

英文版请见仓库根目录 [README.md](../../README.md)。

- [Isolation（中文说明）](#isolation中文说明)
  - [1. 本仓库做什么](#1-本仓库做什么)
  - [2. 本仓库不做什么](#2-本仓库不做什么)
  - [3. 仓库结构](#3-仓库结构)
  - [4. 前置条件](#4-前置条件)
  - [5. 快速开始](#5-快速开始)
  - [6. 用法（main.sh）](#6-用法mainsh)
  - [7. 配置](#7-配置)
    - [7.1. `isolation/isolation.env`](#71-isolationisolationenv)
    - [7.2. `default-user-environment/config.env`](#72-default-user-environmentconfigenv)
  - [8. Shell 启动与 `umask`](#8-shell-启动与-umask)
  - [9. Docker 冒烟测试](#9-docker-冒烟测试)
  - [10. 已知限制与运维说明](#10-已知限制与运维说明)
  - [11. 设计文档索引](#11-设计文档索引)

---

面向共享 Linux 科研服务器的轻量隔离脚本：单一入口 **`main.sh`** 负责初始化主机目录、隔离用户，并在默认情况下按 [main.typ](main.typ) 与 [default.typ](default.typ) 所述配置协作软件树与每用户默认环境。

刻意保持简单，不追求完整多租户平台。

## 1. 本仓库做什么

- **`/data` 布局**：挂载点 `755`，共享数据集在 `/data/shared`（组 `shared_ro`，默认模式 `2775`，见 [main.typ](main.typ)）
- **每用户**：主目录与 `/data/<用户名>_data` 为 `700`，可选加入 `shared_ro`
- **默认**（同一次运行）：`/data/shared_software` 为 `3775`、`software` 组、`~/software` 符号链接，以及从 `template/` 复制的可选文件（`bashrc.sh`、`zshrc.sh`、`config.fish`、`vimrc` / `vimrc.sh`、可选 `install_miniconda.sh`——模板由你维护；脚本只负责复制或执行）
- **演练**：`DRY_RUN=1` 或 `main.sh --dry-run`

若只需要 main.typ 中的目录布局、不需要默认环境步骤，可使用 `main.sh --no-default-user-env`。

## 2. 本仓库不做什么

- 不做 CPU、内存或进程数限制（未集成 cgroup/配额）
- 不做容器级隔离（非 Docker/LXC 方案）
- 不自动加固 sshd、PAM 或审计策略

若需要更强隔离或资源控制，请另行叠加相应机制。

## 3. 仓库结构

```text
.
├── main.sh                              # 入口（sudo ./main.sh 用户 数据根 …）
├── isolation/                           # 主机与用户开通（由 main.sh 调用）
├── default-user-environment/            # 共享软件与用户默认（由 main.sh 调用）
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
sudo ./main.sh alice /data
```

将初始化 `/data` 与 `/data/shared`，创建用户 `alice` 及其 `/data/alice_data`，并应用默认共享软件环境（除非加上 `--no-default-user-env`）。

## 6. 用法（main.sh）

```bash
sudo ./main.sh 用户名 数据目录 [选项…]
```

`数据目录` 须为绝对路径（例如 `/data`）；本次运行中作为 `DATA_ROOT`。

选项：

- `--join-shared-ro` / `--no-join-shared-ro`：是否将用户加入 `shared_ro`（默认：加入）
- `--uid UID`、`--shell PATH`
- `--dry-run`：仅打印将要执行的操作
- `--no-default-user-env`：跳过共享软件初始化、模板与 `~/software` 相关步骤
- `--with-default-user-env`：显式启用默认环境（与省略上述「关闭」类标志相同）
- `--no-join-software`、`--skip-templates`、`--force-templates`、`--install-miniconda`：仅在默认用户环境阶段生效

示例：

```bash
sudo ./main.sh bob /mnt/research-data --no-join-shared-ro
sudo ./main.sh carol /data --uid 2301 --shell /bin/zsh
sudo ./main.sh dave /data --dry-run
sudo ./main.sh erin /data --no-default-user-env
sudo ./main.sh frank /data --install-miniconda
```

## 7. 配置

可用环境变量覆盖默认值；若在当前 shell 中已 export，请使用 `sudo -E ./main.sh …`。

### 7.1. `isolation/isolation.env`

- `DATA_ROOT`（默认 `/data`——通常由 `main.sh` 通过 `数据目录` 传入）
- `SHARED_GROUP`、`SHARED_MODE`（默认 `shared_ro`、`2775`）
- `DEFAULT_LOGIN_SHELL`、`USER_DATA_PREFIX`、`USER_DATA_SUFFIX`（`_data`）
- `USER_UMASK_HINT`、`DRY_RUN`、`ISOLATION_BASHRC_MARK`

### 7.2. `default-user-environment/config.env`

在默认用户环境阶段加载；在 `isolation.env` 基础上扩展：

- `SOFTWARE_ROOT`、`SOFTWARE_GROUP`、`SOFTWARE_MODE`（`3775`）
- `USER_SOFTWARE_LINK_NAME`（`software`）
- `TEMPLATE_DIR`（默认同仓库 `template/`）
- `ENABLE_SOFTWARE_AREA`（`1`；设为 `0` 可关闭该阶段）

## 8. Shell 启动与 `umask`

对所选登录 shell，`main.sh` 创建用户时可能会追加一次性 `umask` 提示。默认环境运行时，在复制模板后也可能向已有 `~/.bashrc`、`~/.zshrc`、`~/.config/fish/config.fish` 追加相同标记。

## 9. Docker 冒烟测试

```bash
./tests/docker-verify.sh
```

在容器内做端到端权限检查（默认镜像 `ubuntu:24.04`；若本地无则拉取）。可选：`./tests/docker-verify.sh 其他镜像` 或设置环境变量 `USER_A` / `USER_B` / `USER_C`。

## 10. 已知限制与运维说明

- 隔离基于权限（UID/GID + 模式），不是沙箱
- root 按设计可访问全部数据
- 更严格的共享：可在运行 `main.sh` 前通过环境变量设置，例如 `SHARED_MODE=0750`
- 新增附属组后需新会话（`newgrp` 或重新登录）后 `id` 才会显示

## 11. 设计文档索引

- [main.typ](main.typ) — 账户与目录隔离
- [default.typ](default.typ) — 协作软件目录、模板、可选 Miniconda

英文设计说明源文件：[doc/en/main.typ](../en/main.typ)、[doc/en/default.typ](../en/default.typ)。
