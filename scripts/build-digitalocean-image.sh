#!/usr/bin/env bash
set -euo pipefail

readonly DIGITALOCEAN_TOKEN="${DIGITALOCEAN_TOKEN:?DIGITALOCEAN_TOKEN is required}"

run_doctl() {
  DIGITALOCEAN_ACCESS_TOKEN="${DIGITALOCEAN_TOKEN}" doctl --context default "$@"
}

for executable in doctl packer ssh-keygen; do
  if ! command -v "${executable}" >/dev/null 2>&1; then
    echo "Required executable is missing: ${executable}" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d)"
private_key="${work_dir}/id_ed25519"
key_name="packer-ci-fab-runner-$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
ssh_key_id=""

cleanup() {
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

export PKR_VAR_ssh_key_id="${ssh_key_id}"
export PKR_VAR_ssh_private_key_file="${private_key}"
packer build packer/digitalocean.pkr.hcl
