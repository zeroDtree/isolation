set -e

# rootless docker
sudo apt install -y uidmap
sudo systemctl disable --now docker.service docker.socket
sudo rm -f /var/run/docker.sock
# sudo apt  -y install -y docker-ce-rootless-extras