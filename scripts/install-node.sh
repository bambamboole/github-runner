#!/usr/bin/env bash
set -euo pipefail

readonly NODE_VERSION="${NODE_VERSION:?NODE_VERSION is required}"
readonly TARGETARCH="${TARGETARCH:?TARGETARCH is required}"

case "${TARGETARCH}" in
  amd64)
    node_arch="x64"
    ;;
  arm64)
    node_arch="arm64"
    ;;
  *)
    echo "Unsupported Node.js architecture: ${TARGETARCH}" >&2
    exit 1
    ;;
esac

asset="node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"
release_url="https://nodejs.org/dist/v${NODE_VERSION}"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT

curl --fail --silent --show-error --location \
  "${release_url}/${asset}" \
  --output "${work_dir}/${asset}"
curl --fail --silent --show-error --location \
  "${release_url}/SHASUMS256.txt" \
  --output "${work_dir}/SHASUMS256.txt"

expected_checksum="$(awk -v asset="${asset}" '$2 == asset { print $1; exit }' "${work_dir}/SHASUMS256.txt")"
if [[ -z "${expected_checksum}" ]]; then
  echo "No checksum found for ${asset}." >&2
  exit 1
fi

actual_checksum="$(sha256sum "${work_dir}/${asset}" | awk '{ print $1 }')"
if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
  echo "Node.js checksum verification failed for ${asset}." >&2
  exit 1
fi

tar -xJf "${work_dir}/${asset}" --directory /usr/local --strip-components=1
node --version
npm --version
