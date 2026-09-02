#!/usr/bin/env bash
set -euo pipefail

readonly DOCKER_KEY_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

export DEBIAN_FRONTEND=noninteractive

cloud-init status --wait
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  sudo \
  ufw \
  unzip \
  xz-utils

if ! id runner >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash runner
fi

install -d -m 0755 /etc/apt/keyrings
curl --fail --silent --show-error --location \
  https://download.docker.com/linux/ubuntu/gpg \
  --output /etc/apt/keyrings/docker.asc

actual_fingerprint="$(gpg --show-keys --with-colons /etc/apt/keyrings/docker.asc | awk -F: '$1 == "fpr" { print $10; exit }')"
if [[ "${actual_fingerprint}" != "${DOCKER_KEY_FINGERPRINT}" ]]; then
  echo "Unexpected Docker signing key fingerprint: ${actual_fingerprint}" >&2
  exit 1
fi

chmod a+r /etc/apt/keyrings/docker.asc
ubuntu_codename="$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release)"
printf '%s\n' \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${ubuntu_codename} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y --no-install-recommends \
  containerd.io \
  docker-buildx-plugin \
  docker-ce \
  docker-ce-cli \
  docker-compose-plugin

usermod --append --groups docker,sudo runner
printf '%s\n' 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner
chmod 0440 /etc/sudoers.d/runner

install -d -o runner -g runner -m 0755 \
  /home/runner \
  /ms-playwright \
  /opt/actions-runner \
  /opt/hostedtoolcache

if [[ ! -e /swapfile ]]; then
  fallocate -l 2G /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile
  swapon /swapfile
fi

systemctl enable --now docker
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable
