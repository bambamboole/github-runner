#!/usr/bin/env bash
set -euo pipefail

readonly SNAPSHOT_ID="${1:?Usage: digitalocean-snapshot-smoke.sh SNAPSHOT_ID}"
readonly REGION="${DIGITALOCEAN_REGION:-fra1}"
readonly SIZE="${DIGITALOCEAN_TEST_SIZE:-s-1vcpu-1gb}"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR

if [[ ! "${SNAPSHOT_ID}" =~ ^[0-9]+$ ]]; then
  echo "Snapshot ID must be numeric." >&2
  exit 64
fi

for executable in doctl ssh scp ssh-keygen; do
  if ! command -v "${executable}" >/dev/null 2>&1; then
    echo "Required executable is missing: ${executable}" >&2
    exit 1
  fi
done

run_doctl() {
  if [[ -n "${DIGITALOCEAN_TOKEN:-}" ]]; then
    DIGITALOCEAN_ACCESS_TOKEN="${DIGITALOCEAN_TOKEN}" doctl --context default "$@"
    return
  fi

  doctl "$@"
}

work_dir="$(mktemp -d)"
known_hosts="${work_dir}/known_hosts"
private_key="${work_dir}/id_ed25519"
resource_suffix="$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
key_name="ci-fab-image-smoke-${resource_suffix}"
droplet_name="ci-fab-image-smoke-${resource_suffix}"
ssh_key_id=""
droplet_id=""

cleanup() {
  if [[ -n "${droplet_id}" ]]; then
    run_doctl compute droplet delete --force "${droplet_id}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${ssh_key_id}" ]]; then
    run_doctl compute ssh-key delete --force "${ssh_key_id}" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${work_dir}"
}
trap cleanup EXIT

ssh-keygen -q -t ed25519 -N '' -C "${key_name}" -f "${private_key}"
ssh_key_id="$(run_doctl compute ssh-key create "${key_name}" \
  --public-key "$(<"${private_key}.pub")" \
  --format ID \
  --no-header)"

for attempt in {1..12}; do
  if run_doctl compute ssh-key get "${ssh_key_id}" >/dev/null 2>&1; then
    break
  fi
  if [[ "${attempt}" -eq 12 ]]; then
    echo "Temporary SSH key did not become available in DigitalOcean." >&2
    exit 1
  fi
  sleep 5
done

droplet_id="$(run_doctl compute droplet create "${droplet_name}" \
  --image "${SNAPSHOT_ID}" \
  --region "${REGION}" \
  --size "${SIZE}" \
  --ssh-keys "${ssh_key_id}" \
  --format ID \
  --no-header)"

if [[ ! "${droplet_id}" =~ ^[0-9]+$ ]]; then
  echo "DigitalOcean returned an invalid test Droplet ID." >&2
  exit 1
fi

for attempt in {1..36}; do
  droplet_status="$(run_doctl compute droplet get "${droplet_id}" --format Status --no-header)"
  if [[ "${droplet_status}" == "active" ]]; then
    break
  fi
  if [[ "${attempt}" -eq 36 ]]; then
    echo "Test Droplet did not become active." >&2
    exit 1
  fi
  sleep 5
done

public_ip="$(run_doctl compute droplet get "${droplet_id}" --format PublicIPv4 --no-header)"
if [[ -z "${public_ip}" ]]; then
  echo "Test Droplet has no public IPv4 address." >&2
  exit 1
fi

ssh_options=(
  -i "${private_key}"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="${known_hosts}"
)

for attempt in {1..36}; do
  if ssh "${ssh_options[@]}" "root@${public_ip}" true 2>/dev/null; then
    break
  fi
  if [[ "${attempt}" -eq 36 ]]; then
    echo "SSH did not become available on the test Droplet." >&2
    exit 1
  fi
  sleep 10
done

scp "${ssh_options[@]}" \
  "${TEST_DIR}/docker-smoke.sh" \
  "${TEST_DIR}/rustfs-smoke.sh" \
  "${TEST_DIR}/smoke.sh" \
  "${TEST_DIR}/vm-smoke.sh" \
  "root@${public_ip}:/tmp/"

ssh "${ssh_options[@]}" "root@${public_ip}" \
  'chmod 0755 /tmp/docker-smoke.sh /tmp/rustfs-smoke.sh /tmp/smoke.sh /tmp/vm-smoke.sh && /tmp/vm-smoke.sh'

echo "Snapshot ${SNAPSHOT_ID} booted and passed the VM smoke tests."
