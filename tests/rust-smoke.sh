#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_TOOLCHAIN="1.99.1"
readonly PINNED_TOOLCHAIN="1.95"

for variable in CARGO_HOME RUSTUP_HOME; do
  if [[ -z "${!variable:-}" ]]; then
    echo "${variable} is not set." >&2
    exit 1
  fi
  if [[ ! -w "${!variable}" ]]; then
    echo "${variable} is not writable by $(id --user --name)." >&2
    exit 1
  fi
done

rustup --version
rustc --version | grep -q "^rustc ${DEFAULT_TOOLCHAIN//./\\.} "
cargo --version
cargo clippy --version
cargo fmt --version
wasm-pack --version | grep -qx 'wasm-pack 0\.15\.1'
command -v cmake >/dev/null
test -e /usr/include/openssl/ssl.h

for toolchain in "${DEFAULT_TOOLCHAIN}" "${PINNED_TOOLCHAIN}"; do
  rustup target list --toolchain "${toolchain}" --installed | grep -qx wasm32-unknown-unknown
  rustup component list --toolchain "${toolchain}" --installed | grep -q '^clippy'
  rustup component list --toolchain "${toolchain}" --installed | grep -q '^rustfmt'
done

work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT
cargo new --quiet --lib --vcs none --name smoke "${work_dir}/smoke"
cd "${work_dir}/smoke"
cargo build --quiet
cargo build --quiet --target wasm32-unknown-unknown
cargo clippy --quiet -- --deny warnings
cargo fmt --check

# A pinned rust-toolchain.toml resolves to the installed toolchain without a
# download: nothing but the toolchain file selects it here.
printf '[toolchain]\nchannel = "%s"\n' "${PINNED_TOOLCHAIN}" > rust-toolchain.toml
rustc --version | grep -q "^rustc ${PINNED_TOOLCHAIN//./\\.}\."
rustup toolchain list | grep -q "^${PINNED_TOOLCHAIN//./\\.}-"
cargo build --quiet
