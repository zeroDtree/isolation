# Rootless Docker (Ubuntu)

Rootless Docker is **not** installed by these helpers alone: they only prepare the system and the user. The user completes setup after logging in.

## Preparation (what this repo does)

[`docker/ubuntu/install-rootless-docker-for-user.sh`](../../docker/ubuntu/install-rootless-docker-for-user.sh) (run as root, or via `add-user.sh … --install-rootless-docker`) does the following:

- Ensures the user has **`/etc/subuid` and `/etc/subgid`** lines (fails if missing).
- Runs **`loginctl enable-linger`** when available.
- Adds a one-time block to **`~/.bashrc`**, **`~/.zshrc`** (only if the file exists), and **`~/.config/fish/config.fish`**, exporting `XDG_RUNTIME_DIR`, `DOCKER_HOST`, and `PATH` for environments without a normal user systemd session.

You still need Docker packages on the machine (including **`docker-ce-rootless-extras`** and **`uidmap`**); see [`docker/ubuntu/`](../../docker/ubuntu/) for install and optional disabling of the root daemon.

## After login (install rootless Docker)

```bash
dockerd-rootless-setuptool.sh install
```
