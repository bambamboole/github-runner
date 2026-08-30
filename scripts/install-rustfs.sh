#!/usr/bin/env bash
set -euo pipefail

readonly RUSTFS_VERSION="${RUSTFS_VERSION:?RUSTFS_VERSION is required}"
readonly TARGETARCH="${TARGETARCH:?TARGETARCH is required}"

case "${TARGETARCH}" in
  amd64)
    rustfs_arch="x86_64"
    ;;
  arm64)
    rustfs_arch="aarch64"
    ;;
  *)
    echo "Unsupported RustFS architecture: ${TARGETARCH}" >&2
    exit 1
    ;;
esac

asset="rustfs-linux-${rustfs_arch}-gnu-v${RUSTFS_VERSION}.zip"
release_url="https://github.com/rustfs/rustfs/releases/download/${RUSTFS_VERSION}"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT

curl --fail --silent --show-error --location \
  "${release_url}/${asset}" \
  --output "${work_dir}/${asset}"
curl --fail --silent --show-error --location \
  "${release_url}/SHA256SUMS" \
  --output "${work_dir}/SHA256SUMS"

expected_checksum="$(awk -v asset="${asset}" '$2 == asset { print $1; exit }' "${work_dir}/SHA256SUMS")"
if [[ -z "${expected_checksum}" ]]; then
  echo "No checksum found for ${asset}." >&2
  exit 1
fi

actual_checksum="$(sha256sum "${work_dir}/${asset}" | awk '{ print $1 }')"
if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
  echo "RustFS checksum verification failed for ${asset}." >&2
  exit 1
fi

unzip -q "${work_dir}/${asset}" -d "${work_dir}/extracted"
install -m 0755 "${work_dir}/extracted/rustfs" /usr/local/bin/rustfs
/usr/local/bin/rustfs --version
