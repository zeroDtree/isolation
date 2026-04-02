
#set document(
  title: "服务器权限隔离设计（用户级）",
  author: "Administrator",
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
// -- Main content ------------------------------------------------------------

= 服务器权限隔离设计（用户级）

本文描述一种基于 Linux 账户与*目录权限*的多用户隔离方案，面向共享科研服务器。每个用户拥有独立的系统账户与主目录，通过同一 SSH 服务、各自用户名登录；数据按用户目录划分，跨用户可见性由 UID/GID 与文件权限限制。*本文不涉及 CPU、内存、进程数配额或 cgroup 限制*；若需要可另行叠加。

== 设计目标

- *安全隔离*：各用户主目录与私有数据目录对他人不可读；共享数据只读或受控可写。
- *运维简单*：账户与目录权限用 `useradd`、`chown`、`chmod`、用户组等标准工具管理。
- *使用友好*：统一 SSH 入口（单端口），按用户名区分会话。

== 总体架构

```
Host machine (single Linux system)
├── SSH service (sshd, usually port 22)
│   ├── User user_a (UID 1001) -> login shell session
│   ├── User user_b (UID 1002) ...
│   └── User user_c (UID 1003) ...
├── Shared data area: /data/shared (managed by root or dedicated group)
└── User private data areas: /data/{username} (owned by that user)
```

通过 `ssh user_a@host` 登录后，进程以该用户 UID 运行，仅能访问对该 UID/组授权的路径。该模型用 UID/GID 与文件权限控制访问，进程仍共享主机同一内核命名空间。共享数据集可通过只读挂载或严格目录权限（例如 `755`、root 属主、对他人只读）降低误删风险。

== 目录与数据布局

```
Host filesystem:
/data/
├── shared/          # shared datasets (read-only or group-read-only)
│   ├── ImageNet/
│   ├── COCO/
│   └── ...
├── user_a/          # private for user A (owner user_a, mode 700)
├── user_b/
└── user_c/
```

- 用户可在其 UID 拥有的目录下读写，在权限正确配置的前提下不能读取他人的 `/home/*` 或 `/data/*`。
- 顶层 `/data` 建议为 `root:root`、`755`，便于挂载点与路径统一管理。
- 共享目录由 root 或 `shared_ro` 管理，避免 `o+w`；必要时使用带 sticky 的子目录或专用上传区。
- 系统软件由 root 安装；用户级 Python/conda 环境放在各自主目录。

== 账户与权限规则

=== 用户与组

- 每位研究者应使用*独立登录账户*（例如 `user_a`），*禁止共用账户*。
- 用户名宜为小写字母、数字、下划线或连字符（例如 `user-a`、`user_a`），并以字母或下划线开头，与脚本校验规则一致。
- 共享只读访问：创建组 `shared_ro`，将需要数据集访问的用户加入该组。共享目录可对组 `shared_ro` 使用 `2775` 或 `0750`，视是否需要组内协作写权限而定。


=== 主目录与数据目录

- `/home/{username}` 建议权限 `700`（`drwx------`），避免被其他用户遍历或列出。
- 大体量数据宜放在独立盘路径如 `/data/{username}`，`chown {username}:{username}` 且模式 `700`；日常开发可仍在主目录 `~`。
- 建议默认 `umask` 为 `027` 或 `077`（详见下文「八进制、特殊位与 umask」）。可在 `/etc/profile` 或各用户 shell 启动文件中配置。

== 登录与访问示例

用户以系统账户直连主机（单端口 22）。下表与下方 `Host` 配置示例对应。

#table(
  columns: (auto, auto, auto),
  align: center,
  table.header([*用户*], [*示例 UID*], [*SSH*]),
  [user_a], [1001], [`ssh user_a@host`],
  [user_b], [1002], [`ssh user_b@host`],
  [user_c], [1003], [`ssh user_c@host`],
  [...], [...], [...],
)

```bash
# Configure in ~/.ssh/config (user A example)
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

登录后得到标准 Linux shell 会话，工作目录为 `~`，类似常见实验室工作站。

= 权限基础

Linux 文件与目录采用*自主访问控制（DAC）*：每个对象有*属主*与*属组*，权限按*属主 / 组 / 其他*判定。每类可有读 `r`、写 `w`、执行 `x`。对文件：`r`/`w` 控制读写内容，`x` 控制是否可执行。对目录：`r` 可列出项，`w` 可创建/删除名字，`x` 可路径穿越。

- *与登录的关系*：登录后进程以该用户 *UID* 运行。内核按 属主→组→其他 顺序检查权限，若无匹配则拒绝访问（在未使用 ACL 等扩展的前提下）。
- *数字写法*：常用八进制模式；`700` 即 `rwx------`，`755` 即 `rwxr-xr-x`，与本文对私有目录与共享目录的建议一致。
- *常用命令*：`chown` 改属主/组，`chmod` 改模式。新建对象的默认模式受 `umask` 与特殊位规则影响，见下文「八进制、特殊位与 umask」。协作相关的共享模式如 `2775` 见「用户与组」。

== 符号模式（`ls -l` 第一列 10 个字符）

`ls -l` 输出的模式串从左到右含义如下（与 `stat` 等工具一致）：

- *第 1 位（类型）*：`-` 普通文件，`d` 目录，`l` 符号链接等；本文主要用 `-` 与 `d`。
- *第 2–4、5–7、8–10 位（三组各 3 位）*：分别表示*用户*、*组*、*其他*。每组内为 `r`、`w`、`x`，缺失为 `-`。例如 `rwxr-xr-x` 表示属主读写执行，组与其他读+执行。
- *目录的 `x`*：对目录若无执行位，通常无法 `cd` 进入（或经该路径解析），这与仅有 `r` 列出目录项不同。
- *特殊执行位标记*：除 `x`、`-` 外，执行位还可显示 `s`/`S`（用户段 setuid、组段 setgid）或 `t`/`T`（其他段 sticky，常见于目录）。八进制对应与含义见下一节。

== 八进制、特殊位与 umask

*三位八进制 `chmod XYZ`*：从左到右为*用户 / 组 / 其他*。每位为 0–7，由 `r=4`、`w=2`、`x=1` 相加（缺位为 0）。例如 `7`=`4+2+1` 为 `rwx`，`5`=`4+1` 为 `r-x`。

*四位八进制 `chmod SXYZ`*：最左 `S` 为*特殊位*之和——`4` setuid（可执行文件上有效用户常为文件属主）、`2` setgid（可执行文件上有效组；在目录上新建文件/子目录常*继承目录属组*）、`1` sticky（目录上仅文件属主、目录属主或 root 可删/改名他人文件；典型如 `/tmp`）。右侧 `XYZ` 与普通权限相同。例：`2775` = `2`（目录 setgid）+ `775`（`rwxrwxr-x`），符号常写作 `drwxrwsr-x`。

*`ls -l` 中的 `s`/`S` 与 `t`/`T`*：特殊位占执行位。若同时有执行位则显示小写 `s`/`t`；若仅有特殊位而无执行则显示大写 `S`/`T`。

*`umask`*：进程创建文件/目录时，内核对默认模式应用掩码。文件典型默认 `0666`，目录 `0777`。有效模式去掉 `umask` 中为 1 的位，等价于对低 9 位 `mode = default & ~umask`。例如 `umask 027` 常得到新文件 `0640`（`rw-r-----`）、新目录 `0750`（`rwxr-x---`）；`umask 077` 常得到文件 `0600`、目录 `0700`。在 `/etc/profile` 或用户 shell 启动文件中配置 `umask` 可减少对组/其他的意外暴露，与「主目录与数据目录」中的建议一致。
