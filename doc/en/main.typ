
#set document(
  title: "Server Permission Isolation Design (User Level)",
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
  lang: "en",
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

= Server Permission Isolation Design (User Level)

This document describes a multi-user isolation design based on Linux accounts and *directory permissions*, intended for shared research servers. Each user has an independent system account and home directory, and logs in through a single SSH service with their own username. Data is split by user directories, and cross-user visibility is restricted through UID/GID and file permissions. *This document does not cover CPU, memory, process-count quotas, or cgroup limits*; those can be added separately if needed.

== Design Goals

- *Security isolation*: each user's home and private data directories are unreadable to others; shared data is read-only or controlled writable.
- *Operational simplicity*: account and directory permissions are managed with standard tools such as `useradd`, `chown`, `chmod`, and groups.
- *User-friendly access*: a unified SSH entry point (single port) with session separation by username.

== Overall Architecture

```
Host machine (single Linux system)
├── SSH service (sshd, usually port 22)
│   ├── User user_a (UID 1001) -> login shell session
│   ├── User user_b (UID 1002) ...
│   └── User user_c (UID 1003) ...
├── Shared data area: /data/shared_data (managed by root or dedicated group; configurable)
└── User private data areas: /data/{username} (owned by that user)
```

After login through `ssh user_a@host`, processes run under that user's UID and can only access paths authorized to that UID/group. This model controls access with UID/GID and file permissions, while processes still share the same kernel namespace on the host. Shared datasets can be protected from accidental deletion by read-only mounts or strict directory modes (for example `755` with root ownership and read-only access for others).

== Directory and Data Layout

```
Host filesystem:
/data/
├── shared_data/     # shared datasets (read-only or group-read-only; name configurable)
│   ├── ImageNet/
│   ├── COCO/
│   └── ...
├── user_a/          # private for user A (owner user_a, mode 700)
├── user_b/
└── user_c/
```

- Users can read/write directories they own under their UID and cannot read other users' `/home/*` or `/data/*` (assuming correct permissions).
- The top-level `/data` directory is recommended as `root:root` with mode `755`, for consistent mount point and path entry management.
- Shared directories are managed by root or `shared_ro`, without `o+w`; if needed, use sticky-bit subdirectories or dedicated upload areas.
- System software is installed by root; user-level Python/conda environments stay in each user's own home.

== Account and Permission Rules

=== Users and Groups

- Each researcher should have one *login account* (for example `user_a`), and *shared accounts must be avoided*.
- Usernames should use lowercase letters, numbers, underscores, or hyphens (for example `user-a`, `user_a`) and start with a letter or underscore, consistent with script validation rules.
- For shared read access, create group `shared_ro` and add users who need dataset access. Shared directories can use group `shared_ro` with mode `3775` (setgid + sticky + group-writable, default in `init-host.sh`), `2775` (setgid only), or `0750`, depending on whether sticky and group collaboration write access are needed.


=== Home and Data Directories

- Recommended permission for `/home/{username}` is `700` (`drwx------`) to prevent traversal or listing by other users.
- Large data should be placed on a separate disk path such as `/data/{username}`, owned by `chown {username}:{username}` with mode `700`; day-to-day work can remain in home `~`.
- Recommended default `umask` is `027` or `077` (details in "Octal, special bits, and umask" below). It can be configured in `/etc/profile` or in user shell startup files.

== Login and Access Examples

Users connect directly to the host with system accounts (single port 22). The table matches the `Host` config example below.

#table(
  columns: (auto, auto, auto),
  align: center,
  table.header([*User*], [*Example UID*], [*SSH*]),
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

After login, the user gets a standard Linux shell session with working directory `~`, similar to a typical lab workstation.

= Permission Primer

Linux files and directories use *Discretionary Access Control (DAC)*: each object has an *owner* and *group*, and permissions are evaluated for *owner / group / others*. Each class may have read `r`, write `w`, and execute `x`. For files, `r`/`w` control content read/write and `x` controls executability. For directories, `r` allows listing entries, `w` allows creating/removing names, and `x` allows path traversal.

- *Relation to login*: after login, processes run with that user's *UID*. The kernel checks permissions in owner/group/other order and denies access if none match (assuming no ACL or other extensions).
- *Numeric notation*: octal modes are commonly used; `700` means `rwx------`, and `755` means `rwxr-xr-x`, matching private and shared directory recommendations in this document.
- *Common commands*: use `chown` to change owner/group and `chmod` to change modes. Default modes for newly created objects are affected by `umask` and special-bit rules, described in "Octal, special bits, and umask" below. Collaboration-related shared modes such as `3775` and `2775` are discussed in "Users and Groups".

== Symbolic Mode (`ls -l` first column, 10 characters)

The mode string from `ls -l` maps left-to-right as follows (consistent with tools like `stat`):

- *Position 1 (type)*: `-` regular file, `d` directory, `l` symlink, etc. This document mainly uses `-` and `d`.
- *Positions 2-4, 5-7, 8-10 (three groups of 3)*: represent *user*, *group*, and *other*. Within each group, bits are `r`, `w`, `x`; missing bits are `-`. For example, `rwxr-xr-x` means owner read/write/execute, group read/execute, other read/execute.
- *Directory `x`*: for directories, without execute permission you usually cannot `cd` into that directory (or resolve paths through it), which is different from having `r` to list entries.
- *Special execute markers*: besides `x` and `-`, execute positions can show `s`/`S` (setuid in user section, setgid in group section) or `t`/`T` (sticky in other section, commonly on directories). See the next section for octal mapping and meaning.

== Octal, Special Bits, and umask

*Three-digit octal `chmod XYZ`*: from left to right these are *user / group / other*. Each digit is 0-7, formed by `r=4`, `w=2`, `x=1` (missing bits add 0). For example, `7`=`4+2+1` gives `rwx`, and `5`=`4+1` gives `r-x`.

*Four-digit octal `chmod SXYZ`*: the leftmost `S` is the sum of *special bits* - `4` for setuid (on executables, effective user is often file owner), `2` for setgid (on executables, effective group; on directories, new files/subdirectories commonly *inherit directory group*), and `1` for sticky (on directories, only file owner, directory owner, or root can delete/rename others' files; classic example `/tmp`). The trailing `XYZ` are the same as normal permissions. Example: `3775` = `3` (sticky + directory setgid) + `775` (`rwxrwxr-x`), often shown symbolically with both `s` and `t`. Example: `2775` = `2` (directory setgid only) + `775`, often `drwxrwsr-x`.

*`s`/`S` and `t`/`T` in `ls -l`*: special bits occupy execute positions. If execute is also set, lowercase `s`/`t` is shown; if execute is not set and only special bit exists, uppercase `S`/`T` is shown.

*`umask`*: when processes create files/directories, the kernel applies a mask to default modes. Typical defaults are `0666` for *files* and `0777` for *directories*. Effective mode removes bits that are 1 in `umask`, equivalent to `mode = default & ~umask` (for the lower 9 permission bits). For example, `umask 027` usually yields new files `0640` (`rw-r-----`) and new directories `0750` (`rwxr-x---`); `umask 077` usually yields files `0600` and directories `0700`. Configuring `umask` in `/etc/profile` or user shell startup files reduces accidental exposure to group/others, consistent with recommendations in "Home and Data Directories".
