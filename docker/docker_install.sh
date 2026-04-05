
#!/bin/bash
set -e

MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu"
# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL $MIRROR_URL/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: $MIRROR_URL
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# Update the package index and install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# start docker
sudo systemctl status docker
sudo systemctl start docker

# exit 0

# rootless docker
sudo apt install -y uidmap
sudo systemctl disable --now docker.service docker.socket
sudo rm /var/run/docker.sock
# sudo apt  -y install -y docker-ce-rootless-extras
dockerd-rootless-setuptool.sh install
docker info