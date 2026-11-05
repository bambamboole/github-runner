#!/usr/bin/env bash
set -euo pipefail

readonly RUST_TOOLCHAINS="${RUST_TOOLCHAINS:?RUST_TOOLCHAINS is required}"
readonly RUSTUP_VERSION="${RUSTUP_VERSION:?RUSTUP_VERSION is required}"
readonly TARGETARCH="${TARGETARCH:?TARGETARCH is required}"
readonly WASM_PACK_VERSION="0.15.1"

export RUSTUP_HOME="${RUSTUP_HOME:-/usr/local/rustup}"
export CARGO_HOME="${CARGO_HOME:-/usr/local/cargo}"
export DEBIAN_FRONTEND=noninteractive

case "${TARGETARCH}" in
  amd64)
    rust_arch="x86_64"
    wasm_pack_checksum="410101009739b9d01c7d5affaaad6e9c9a24b4cba6791a4805db8e89b9bf7af2"
    ;;
  arm64)
    rust_arch="aarch64"
    wasm_pack_checksum="7004853c7925ae1984033b5f25866ec604bbc921ef956d5e6c5595bc5af6d30c"
    ;;
  *)
    echo "Unsupported Rust architecture: ${TARGETARCH}" >&2
    exit 1
    ;;
esac

# Native crates such as aws-lc-sys and openssl-sys build against these.
apt-get update
apt-get install -y --no-install-recommends cmake libssl-dev

work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT

rustup_url="https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${rust_arch}-unknown-linux-gnu/rustup-init"
curl --fail --silent --show-error --location "${rustup_url}" --output "${work_dir}/rustup-init"
expected_checksum="$(curl --fail --silent --show-error --location "${rustup_url}.sha256" | awk '{ print $1 }')"
printf '%s  %s\n' "${expected_checksum}" "${work_dir}/rustup-init" | sha256sum --check --status
chmod 0755 "${work_dir}/rustup-init"
"${work_dir}/rustup-init" -y --no-modify-path --profile minimal --default-toolchain none

"${CARGO_HOME}/bin/rustup" set auto-self-update disable

# The first toolchain becomes the default. Installing another one keeps a job
# whose rust-toolchain.toml names it from downloading it on every droplet.
read -r -a toolchains <<< "${RUST_TOOLCHAINS}"
for toolchain in "${toolchains[@]}"; do
  "${CARGO_HOME}/bin/rustup" toolchain install "${toolchain}" \
    --profile minimal \
    --component clippy \
    --component rustfmt \
    --target wasm32-unknown-unknown \
    --no-self-update
done
"${CARGO_HOME}/bin/rustup" default "${toolchains[0]}"

wasm_pack_name="wasm-pack-v${WASM_PACK_VERSION}-${rust_arch}-unknown-linux-musl"
wasm_pack_url="https://github.com/wasm-bindgen/wasm-pack/releases/download/v${WASM_PACK_VERSION}/${wasm_pack_name}.tar.gz"
curl --fail --silent --show-error --location "${wasm_pack_url}" --output "${work_dir}/wasm-pack.tar.gz"
printf '%s  %s\n' "${wasm_pack_checksum}" "${work_dir}/wasm-pack.tar.gz" | sha256sum --check --status
tar -xzf "${work_dir}/wasm-pack.tar.gz" --directory "${work_dir}"
install -m 0755 "${work_dir}/${wasm_pack_name}/wasm-pack" "${CARGO_HOME}/bin/wasm-pack"

# Jobs run as this user and write the registry cache and further toolchains here.
chown -R runner:runner "${RUSTUP_HOME}" "${CARGO_HOME}"

"${CARGO_HOME}/bin/rustc" --version
"${CARGO_HOME}/bin/cargo" --version
"${CARGO_HOME}/bin/wasm-pack" --version
