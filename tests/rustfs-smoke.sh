#!/usr/bin/env bash
set -euo pipefail

runner_temp="$(mktemp -d /tmp/rustfs-smoke.XXXXXX)"
export RUNNER_TEMP="${runner_temp}"
export RUSTFS_ACCESS_KEY="ci-access-key"
export RUSTFS_SECRET_KEY="ci-secret-key-that-is-not-used-outside-the-test"
export RUSTFS_BUCKET="ci-smoke-bucket"

cleanup() {
  rustfs-ci stop >/dev/null 2>&1 || true
  rm -rf -- "${runner_temp}"
}
trap cleanup EXIT

rustfs-ci start
rustfs-ci status

printf 'rustfs smoke test\n' > "${runner_temp}/input.txt"
AWS_ACCESS_KEY_ID="${RUSTFS_ACCESS_KEY}" \
AWS_SECRET_ACCESS_KEY="${RUSTFS_SECRET_KEY}" \
AWS_DEFAULT_REGION="us-east-1" \
  aws --endpoint-url http://127.0.0.1:9000 \
  s3 cp "${runner_temp}/input.txt" "s3://${RUSTFS_BUCKET}/input.txt" >/dev/null

AWS_ACCESS_KEY_ID="${RUSTFS_ACCESS_KEY}" \
AWS_SECRET_ACCESS_KEY="${RUSTFS_SECRET_KEY}" \
AWS_DEFAULT_REGION="us-east-1" \
  aws --endpoint-url http://127.0.0.1:9000 \
  s3 cp "s3://${RUSTFS_BUCKET}/input.txt" "${runner_temp}/output.txt" >/dev/null

cmp "${runner_temp}/input.txt" "${runner_temp}/output.txt"
rustfs-ci stop
rustfs-ci stop

if [[ -e "${runner_temp}/rustfs-ci/pid" ]]; then
  echo "RustFS PID file remains after stop." >&2
  exit 1
fi

fake_bin="${runner_temp}/fake-bin"
mkdir -p "${fake_bin}"
printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "${fake_bin}/aws"
chmod 0755 "${fake_bin}/aws"
export RUSTFS_BUCKET="ci-failed-bucket"

if PATH="${fake_bin}:${PATH}" rustfs-ci start; then
  echo "RustFS start unexpectedly succeeded with a failing S3 client." >&2
  exit 1
fi

if [[ -e "${runner_temp}/rustfs-ci/pid" ]]; then
  echo "RustFS PID file remains after a failed start." >&2
  exit 1
fi

if compgen -G "${runner_temp}/rustfs-data.*" >/dev/null; then
  echo "Managed RustFS data remains after a failed start." >&2
  exit 1
fi
