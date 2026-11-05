#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR

cloud_init_exit=0
cloud-init status --wait || cloud_init_exit=$?
if [[ "${cloud_init_exit}" -ne 0 ]]; then
  cloud-init status --long >&2 || true
  grep -B 5 -A 20 'Failed pickling datasource' /var/log/cloud-init.log >&2 || true
  exit "${cloud_init_exit}"
fi

id runner
id --groups --name runner | tr ' ' '\n' | grep -qx docker
sudo -u runner -H sudo -n true

test -x /opt/actions-runner/run.sh
test -x /opt/actions-runner/bin/Runner.Listener

for runner_state in .credentials .credentials_rsaparams .runner _diag _work; do
  if [[ -e "/opt/actions-runner/${runner_state}" ]]; then
    echo "Runner state leaked into the image: ${runner_state}" >&2
    exit 1
  fi
done

sudo -u runner -H /opt/actions-runner/bin/Runner.Listener --version | grep -qx '2\.337\.0'
rm -rf /opt/actions-runner/_diag

grep -qx 'PLAYWRIGHT_BROWSERS_PATH=/ms-playwright' /opt/actions-runner/.env
grep -qx 'RUNNER_TOOL_CACHE=/opt/hostedtoolcache' /opt/actions-runner/.env
grep -qx 'CARGO_HOME=/usr/local/cargo' /opt/actions-runner/.env
grep -qx 'RUSTUP_HOME=/usr/local/rustup' /opt/actions-runner/.env

systemctl is-enabled --quiet docker
systemctl is-active --quiet docker
if systemctl is-enabled --quiet valkey-server.service || systemctl is-active --quiet valkey-server.service; then
  echo "Valkey must not start on its own: it would hold the port of a redis service container." >&2
  exit 1
fi
if [[ -n "$(ss -H -ltn 'sport = :6379')" ]]; then
  echo "Port 6379 is taken." >&2
  exit 1
fi
ufw status | grep -q '^Status: active$'

required_executables=(
  cc
  c++
  dig
  file
  getfacl
  gh
  git-lfs
  make
  nc
  ping
  pip3
  pipx
  pkg-config
  python3
  redis-cli
  rg
  rsync
  shellcheck
  valkey-cli
  yq
  zip
  zstd
)

for executable in "${required_executables[@]}"; do
  command -v "${executable}" >/dev/null
done

git lfs version
gh --version | head -n 1
shellcheck --version | grep -q '^version:'
yq --version | grep -q 'v4\.53\.3$'
printf '%s\n' 'runner:' '  enabled: true' | yq --exit-status '.runner.enabled == true' >/dev/null

venv_dir="$(mktemp -d)"
trap 'rm -rf -- "${venv_dir}"' EXIT
python3 -m venv "${venv_dir}"
"${venv_dir}/bin/pip" --version

sudo -u runner -H sudo -n systemctl start valkey-server.service
for _ in {1..30}; do
  redis-cli ping 2>/dev/null | grep -qx PONG && break
  sleep 1
done
redis-cli ping | grep -qx PONG
sudo -u runner -H redis-cli ping | grep -qx PONG
listeners="$(ss -H -ltn 'sport = :6379' | awk '{ print $4 }')"
if [[ -z "${listeners}" ]] || grep -Eq '^(0\.0\.0\.0|\*|\[::\]):6379$' <<< "${listeners}"; then
  echo "Valkey is not restricted to loopback: ${listeners}" >&2
  exit 1
fi
systemctl stop valkey-server.service

PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
  "${TEST_DIR}/smoke.sh"

sudo -u runner -H env \
  PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
  RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
  "${TEST_DIR}/rustfs-smoke.sh"

sudo -u runner -H "${TEST_DIR}/docker-smoke.sh"

# Exactly the runner's .env, so this proves what a job gets.
# shellcheck disable=SC2046
sudo -u runner -H env --ignore-environment HOME=/home/runner $(cat /opt/actions-runner/.env) "${TEST_DIR}/rust-smoke.sh"
