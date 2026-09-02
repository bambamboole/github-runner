#!/usr/bin/env bash
set -euo pipefail

readonly AWS_CLI_VERSION="${AWS_CLI_VERSION:?AWS_CLI_VERSION is required}"
readonly COMPOSER_VERSION="${COMPOSER_VERSION:?COMPOSER_VERSION is required}"
readonly NODE_VERSION="${NODE_VERSION:?NODE_VERSION is required}"
readonly PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:?PLAYWRIGHT_VERSION is required}"
readonly RUNNER_CHECKSUM="${RUNNER_CHECKSUM:?RUNNER_CHECKSUM is required}"
readonly RUNNER_VERSION="${RUNNER_VERSION:?RUNNER_VERSION is required}"
readonly RUSTFS_VERSION="${RUSTFS_VERSION:?RUSTFS_VERSION is required}"

export PLAYWRIGHT_BROWSERS_PATH="/ms-playwright"
export RUNNER_TOOL_CACHE="/opt/hostedtoolcache"

chmod 0755 \
  /tmp/install-aws-cli.sh \
  /tmp/install-node.sh \
  /tmp/install-php.sh \
  /tmp/install-playwright.sh \
  /tmp/install-rustfs.sh

TARGETARCH=amd64 /tmp/install-aws-cli.sh
/tmp/install-php.sh
TARGETARCH=amd64 /tmp/install-node.sh
/tmp/install-playwright.sh
TARGETARCH=amd64 /tmp/install-rustfs.sh

install -m 0755 /tmp/rustfs-ci /usr/local/bin/rustfs-ci
install -m 0755 /tmp/use-php /usr/local/bin/use-php

runner_asset="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
runner_url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${runner_asset}"
runner_archive="$(mktemp)"
trap 'rm -f -- "${runner_archive}"' EXIT

curl --fail --silent --show-error --location "${runner_url}" --output "${runner_archive}"
printf '%s  %s\n' "${RUNNER_CHECKSUM}" "${runner_archive}" | sha256sum --check --status
tar -xzf "${runner_archive}" --directory /opt/actions-runner
/opt/actions-runner/bin/installdependencies.sh

printf '%s\n' \
  'PLAYWRIGHT_BROWSERS_PATH=/ms-playwright' \
  'RUNNER_TOOL_CACHE=/opt/hostedtoolcache' \
  > /opt/actions-runner/.env

chown -R runner:runner \
  /home/runner \
  /ms-playwright \
  /opt/actions-runner \
  /opt/hostedtoolcache
chmod 0644 /opt/actions-runner/.env
