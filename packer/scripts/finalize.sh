#!/usr/bin/env bash
set -euo pipefail

readonly CLEANUP_CHECKSUM="5e2fe7ce30892a26ed2731238d9f26c40ae8b1084b070ce095f3b99ab1a2cc81"
readonly CLEANUP_URL="https://raw.githubusercontent.com/digitalocean/marketplace-partners/b70878804ca27c01d5f5e882d26485defbaba210/scripts/90-cleanup.sh"
readonly VALIDATOR_CHECKSUM="91ff2b1880439c97ccdc49554c5ed8901b89ef250c8ac5fffe52811c68abac49"
readonly VALIDATOR_URL="https://raw.githubusercontent.com/digitalocean/marketplace-partners/b70878804ca27c01d5f5e882d26485defbaba210/scripts/99-img-check.sh"

if swapon --show=NAME --noheadings | grep -qx /swapfile; then
  swapoff /swapfile
fi
rm -f /swapfile

rm -rf \
  /home/runner/.cache \
  /home/runner/.npm \
  /home/runner/.ssh \
  /opt/actions-runner/.credentials \
  /opt/actions-runner/.credentials_rsaparams \
  /opt/actions-runner/.runner \
  /opt/actions-runner/_diag \
  /opt/actions-runner/_work

docker system prune --all --force --volumes

cleanup_script="/root/90-cleanup.sh"
validator_script="/root/99-img-check.sh"
curl --fail --silent --show-error --location "${CLEANUP_URL}" --output "${cleanup_script}"
curl --fail --silent --show-error --location "${VALIDATOR_URL}" --output "${validator_script}"
printf '%s  %s\n' "${CLEANUP_CHECKSUM}" "${cleanup_script}" | sha256sum --check --status
printf '%s  %s\n' "${VALIDATOR_CHECKSUM}" "${validator_script}" | sha256sum --check --status
chmod 0700 "${cleanup_script}" "${validator_script}"

"${cleanup_script}"
cloud-init clean --logs --machine-id
systemctl stop rsyslog.service syslog.socket
find /var/log -type f -exec truncate --size 0 {} +
"${validator_script}"

if [[ -e /var/lib/cloud/instance || -L /var/lib/cloud/instance ]]; then
  echo "Cloud-init instance state was not removed." >&2
  exit 1
fi

rm -f "${cleanup_script}" "${validator_script}"
sync
