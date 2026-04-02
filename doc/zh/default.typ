#set document(
  title: "默认用户环境与软件目录布局",
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

= 默认用户环境与软件目录布局

本文说明在*已创建系统用户之后*，如何批量或通过自动化准备默认工作环境；前提为*每用户独立账户与目录权限*：每用户自有软件（如 Miniconda）、经符号链接指向的*协作型*共享软件树，以及 Bash、Zsh、Fish、Vim 的默认配置。目标与*服务器权限隔离设计（用户级）*一致：数据与权限按 UID 分离；共享软件区在 Unix 组内可写可用，目录 sticky 位避免用户互删彼此条目。

== 设计原则

- *主目录下的每用户软件*：由该用户拥有并 `chown`，例如 `~/miniconda3` 或 `~/.local`，避免与系统全局安装混杂，便于备份与迁移。
- *协作共享软件目录*：符号链接如 `~/software` 指向同一棵共享树（如 `/data/shared_software`）；成员可在其中*安装或放置*软件、*读取并执行*他人添加的内容，但*不得删除或重命名*非己拥有的条目（目录 sticky `t` 与属主规则；见下文）。
- *可维护的默认配置*：骨架文件放在 `/etc/skel` 或 root 维护的模板目录，通过 `useradd -m -k` 或首次登录/创建后脚本复制到 `~`；敏感信息（API 密钥等）仍由用户自行负责。
- *与权限模型一致*：能否*使用他人软件*取决于文件与目录的读/执行位；能否*删除他人条目*由 sticky 与属主规则及主目录隔离共同决定。

== 每用户软件：Miniconda（示例）

在首次登录前*以目标用户身份*下载安装，或在 `post-create` 脚本中执行（例如 `sudo -u user_a bash …`）。

- 建议安装路径：`$HOME/miniconda3`，仍位于该用户 `700` 主目录树下。

== 共享软件目录与符号链接

设共享树根为 `software_root`（例如 `/data/shared_software`）。预期行为：*所有需要协作的人（或某一 Unix 组全体成员）*可在该树下创建目录与文件、运行他人安装的软件；*仅文件或目录的属主*（及 root）可删除或重命名该条目——与 `/tmp` 的 sticky 思想相同。

建议由 root 一次性配置（示例组名 `software`；可按站点改名）：

```bash
# root: group, directory, sticky + setgid (3775 = setgid + sticky + rwxrwxr-x)
groupadd -f software
mkdir -p /data/shared_software
chown root:software /data/shared_software
chmod 3775 /data/shared_software
# Users must be in this group to create content here; re-login for new groups to apply
usermod -aG software user_a
```

创建用户后，在主目录添加符号链接以提供稳定路径并便于说明：

```bash
# root or provisioning script
ln -sfn /data/shared_software /home/user_a/software
chown -h user_a:user_a /home/user_a/software   # link metadata only; target permissions follow the shared tree
```

若需*组可写、其他只读*：保持目录上*其他*为 `r-x`（`3775` 示例已为 `rwxrwxr-x`，其他为 `r-x`），将需要写入的用户加入 `software`，只读用户不加入该组——依赖已发布文件上的 `o+r` / `o+x`（或站点级 `chmod` 策略）。

== 默认文件复制

- Bash：`~/.bashrc`
- Zsh：`~/.zshrc`
- Fish：`~/.config/fish/config.fish`
- Vim：`~/.vimrc`

