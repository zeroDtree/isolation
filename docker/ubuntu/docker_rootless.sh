#!/bin/bash

set -e

# rootless docker
sudo apt install -y uidmap
sudo systemctl disable --now docker.service docker.socket
sudo rm /var/run/docker.sock
# sudo apt  -y install -y docker-ce-rootless-extras
dockerd-rootless-setuptool.sh install
docker info