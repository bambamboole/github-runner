#!/usr/bin/env bash
set -euo pipefail

readonly AWS_CLI_KEY_FINGERPRINT="FB5DB77FD5C118B80511ADA8A6310ACC4672475C"
readonly AWS_CLI_VERSION="${AWS_CLI_VERSION:?AWS_CLI_VERSION is required}"
readonly TARGETARCH="${TARGETARCH:?TARGETARCH is required}"

case "${TARGETARCH}" in
  amd64)
    aws_arch="x86_64"
    ;;
  arm64)
    aws_arch="aarch64"
    ;;
  *)
    echo "Unsupported AWS CLI architecture: ${TARGETARCH}" >&2
    exit 1
    ;;
esac

work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT
key_file="${work_dir}/aws-cli.asc"
asset="awscli-exe-linux-${aws_arch}-${AWS_CLI_VERSION}.zip"
release_url="https://awscli.amazonaws.com/${asset}"

curl --fail --silent --show-error --location \
  "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${AWS_CLI_KEY_FINGERPRINT}" \
  --output "${key_file}"

actual_fingerprint="$(gpg --show-keys --with-colons "${key_file}" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [[ "${actual_fingerprint}" != "${AWS_CLI_KEY_FINGERPRINT}" ]]; then
  echo "Unexpected AWS CLI signing key fingerprint: ${actual_fingerprint}" >&2
  exit 1
fi

install -d -m 0700 "${work_dir}/gnupg"
gpg --batch --homedir "${work_dir}/gnupg" --import "${key_file}"
curl --fail --silent --show-error --location "${release_url}" --output "${work_dir}/${asset}"
curl --fail --silent --show-error --location "${release_url}.sig" --output "${work_dir}/${asset}.sig"
gpg --batch --homedir "${work_dir}/gnupg" --verify "${work_dir}/${asset}.sig" "${work_dir}/${asset}"

unzip -q "${work_dir}/${asset}" -d "${work_dir}"
"${work_dir}/aws/install" --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
aws --version | grep -q "^aws-cli/${AWS_CLI_VERSION} "
