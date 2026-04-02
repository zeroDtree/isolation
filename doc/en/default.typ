#set document(
  title: "Default User Environment and Software Layout",
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

= Default User Environment and Software Layout

This document describes how to prepare a default working environment in bulk or via automation *after a system user is created*, under the assumption of *per-user accounts and directory permissions*: per-user software (e.g. Miniconda), *collaborative* shared-software trees via symbolic links, and default configuration for Bash, Zsh, Fish, and Vim. The goals align with *Server Permission Isolation Design*: data and permissions are separated by UID; the shared software area is writable and usable within a Unix group, while a directory sticky bit prevents users from deleting each other's entries.

== Design principles

- *Per-user software under the home directory*: owned and `chown`ed by that user (e.g. `~/miniconda3` or `~/.local`), avoiding mixing with system-wide installs and simplifying backup and migration.
- *Collaborative shared software directory*: symbolic links such as `~/software` point at one shared tree (e.g. `/data/shared_software`); members may *install or place* software there, *read and execute* content others added, but *must not delete or rename* entries they do not own (sticky bit `t` on the directory and ownership rules; see below).
- *Maintainable default configuration*: skeleton files live in `/etc/skel` or a root-maintained template directory and are copied to `~` via `useradd -m -k` or a first-login / post-create script; sensitive values (API keys, etc.) remain the user's responsibility.
- *Consistent with the permission model*: whether someone can *use another user's software* depends on read/execute bits on files and directories; whether they can *delete another user's entries* is governed by the sticky bit and ownership, alongside home-directory isolation.

== Per-user software: Miniconda (example)

Download and install *as the target user* before first login or from a `post-create` script (e.g. `sudo -u user_a bash …`).

- Recommended install path: `$HOME/miniconda3`, remaining under that user's `700` home tree.

== Shared software directory and symbolic links

Let the shared tree root be `software_root` (e.g. `/data/shared_software`). The intended behavior: *everyone who should collaborate (or all members of one Unix group)* can create directories and files under that tree and run software others installed; *only the owner of a file or directory* (plus root) may delete or rename that entry—the same idea as the sticky bit on `/tmp`.

Recommended one-time setup by root (example group name `software`; rename per site):

```bash
# root: group, directory, sticky + setgid (3775 = setgid + sticky + rwxrwxr-x)
groupadd -f software
mkdir -p /data/shared_software
chown root:software /data/shared_software
chmod 3775 /data/shared_software
# Users must be in this group to create content here; re-login for new groups to apply
usermod -aG software user_a
```

After creating the user, add a symbolic link in the home directory for a stable path and documentation:

```bash
# root or provisioning script
ln -sfn /data/shared_software /home/user_a/software
chown -h user_a:user_a /home/user_a/software   # link metadata only; target permissions follow the shared tree
```

For *group-writable, others read-only*: keep *others* on the directory as `r-x` (the `3775` example already yields `rwxrwxr-x` with others `r-x`), add every user who should write to `software`, and omit read-only users from the group—relying on `o+r` / `o+x` on published files (or a site-wide `chmod` policy).

== Default file copies

- Bash: `~/.bashrc`
- Zsh: `~/.zshrc`
- Fish: `~/.config/fish/config.fish`
- Vim: `~/.vimrc`

