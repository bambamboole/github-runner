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

systemctl is-enabled --quiet docker
systemctl is-active --quiet docker
ufw status | grep -q '^Status: active$'

PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
  "${TEST_DIR}/smoke.sh"

sudo -u runner -H env \
  PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
  RUNNER_TOOL_CACHE=/opt/hostedtoolcache \
  "${TEST_DIR}/rustfs-smoke.sh"

sudo -u runner -H "${TEST_DIR}/docker-smoke.sh"
