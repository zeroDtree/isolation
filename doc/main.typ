
#set document(
  title: "服务器权限隔离系统设计（用户级）",
  author: "管理员",
  date: datetime.today(),
)
#set page(
  numbering: "1",
  number-align: center,
  margin: (x: 2.5cm, y: 2.5cm),
)
#set text(
  font: ("Noto Serif CJK SC", "New Computer Modern", "Source Han Serif SC"),
  size: 11pt,
  lang: "zh",
)
#set heading(numbering: "1.")
#set par(justify: true, leading: 0.8em)

#show raw.where(block: false): box.with(
  fill: luma(240),
  inset: (x: 3pt, y: 0pt),
  outset: (y: 3pt),
  radius: 2pt,
)
#show raw.where(block: true): block.with(
  fill: luma(240),
  inset: 10pt,
  radius: 4pt,
  width: 100%,
)
#show link: underline
// ── 正文 ────────────────────────────────────────────────────────────────────
= 服务器权限隔离系统设计（用户级）

本文档描述基于 Linux 多账户与*目录权限*的多用户隔离设计，适用于多人共用服务器的科研环境。每位用户拥有独立系统账户与主目录，通过统一 SSH 服务以不同用户名登录；数据按用户划分目录，通过 UID/GID 与文件权限实现互不可见。*本文档不涉及 CPU、内存、任务数等资源的配额或 cgroup 限制*；若日后需要，可另行配置。

== 设计目标

- *安全隔离*：各用户主目录与私有数据目录对他人不可读；共享数据只读或受控可写
- *易于管理*：使用 `useradd`、`chown`、`chmod`、用户组等标准工具完成账户与目录权限配置
- *用户友好*：统一 SSH 入口（单端口），按用户名区分会话

== 整体架构

```
宿主机（单一 Linux 系统）
├── SSH 服务（sshd，通常端口 22）
│   ├── 用户 user_a（UID 1001）→ 登录后 shell 环境
│   │   ├── 主目录 /home/user_a（权限 700，仅本人）
│   │   └── 数据目录 /data/user_a（大容量数据，权限 700，仅本人）
│   ├── 用户 user_b（UID 1002）…
│   └── 用户 user_c（UID 1003）…
├── 共享数据区：/data/shared（root 或专用组管理，对用户只读或受限写）
└── 各用户数据区：/data/{username}（属主为该用户，模式 700 或 750+ACL）
```

用户通过 `ssh user_a@服务器` 登录；进程以该 UID 运行，仅能访问对该 UID/组授权的路径。该方案基于 UID/GID 与文件权限控制访问，同机进程共享内核命名空间。共享数据集通过只读挂载或目录权限（如 `755` + 属主 root、其他人只读）防止误删。

== 账户与权限规范

=== 用户与组

- 每位科研用户对应一个*登录账户*（如 `user_a`），*禁止多人共用同一账户*。
- 为共享只读资源可建组 `shared_ro`，将需读共享数据的用户加入该组；共享目录属组 `shared_ro`，权限 `2775` 或 `0750`（按是否需要组内协作调整）。

=== 主目录与数据目录

- `/home/{username}` 权限建议 `700`（`drwx------`），避免其他用户列举或进入。
- 大容量数据放在独立盘 `/data/{username}`，`chown {username}:{username}`，权限 `700`；日常工作以主目录 `~` 为准。
- 默认 `umask` 可在 `/etc/profile` 或用户 `~/.bashrc` 设为 `027` 或 `077`，减少意外放宽组/世界权限。

== 用户与访问约定

#table(
  columns: (auto, auto, auto),
  align: center,
  table.header([*用户*], [*UID 示例*], [*SSH*]),
  [user_a], [1001], [`ssh user_a@host`],
  [user_b], [1002], [`ssh user_b@host`],
  [user_c], [1003], [`ssh user_c@host`],
  [...], [...], [...],
)

== 用户访问方式

用户使用系统账户直连宿主机（单端口 22）：

```bash
# 在 ~/.ssh/config 中配置（用户 A 示例）
Host my_server
    HostName 10.10.0.240
    User user_a
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
```

```bash
ssh my_server
```

登录后为常规 Linux 会话，工作目录即 `~`，与实验室物理机体验一致。

== 数据目录规范

```
宿主机文件系统：
/data/
├── shared/          # 共享数据集（只读或组内只读）
│   ├── ImageNet/
│   ├── COCO/
│   └── ...
├── user_a/          # 用户A私有（属主 user_a，模式 700）
├── user_b/
└── user_c/
```

- 用户只能在自己的 UID 下读写属主为自己的目录；无法读取他人的 `/home/*`、`/data/*`（在权限配置正确的前提下）。
- 共享目录由 root 或 `shared_ro` 组管理，不写 `o+w`；必要时对子目录设粘滞位或专用上传区。
- 系统目录与软件由 root 安装；用户级 Python/conda 安装在各自主目录，互不覆盖。
