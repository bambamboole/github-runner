#!/usr/bin/env bash
set -euo pipefail

readonly PHP_KEY_FINGERPRINT="B8DC7E53946656EFBCE4C1DD71DAEAAB4AD4CAB6"
readonly PHP_KEYRING="/usr/share/keyrings/ondrej-php.gpg"
readonly COMPOSER_VERSION="${COMPOSER_VERSION:?COMPOSER_VERSION is required}"

# Provided by the Ubuntu base image.
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${VERSION_CODENAME}" != "noble" ]]; then
  echo "PHP installation requires Ubuntu Noble." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg procps

key_file="$(mktemp)"
trap 'rm -f "${key_file}"' EXIT

curl --fail --silent --show-error --location \
  "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${PHP_KEY_FINGERPRINT}" \
  --output "${key_file}"

actual_fingerprint="$(gpg --show-keys --with-colons "${key_file}" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [[ "${actual_fingerprint}" != "${PHP_KEY_FINGERPRINT}" ]]; then
  echo "Unexpected signing key fingerprint: ${actual_fingerprint}" >&2
  exit 1
fi

gpg --dearmor --yes --output "${PHP_KEYRING}" "${key_file}"
printf '%s\n' \
  "deb [signed-by=${PHP_KEYRING}] https://ppa.launchpadcontent.net/ondrej/php/ubuntu noble main" \
  > /etc/apt/sources.list.d/ondrej-php.list

extensions=(
  bcmath
  bz2
  cli
  common
  curl
  dev
  gd
  intl
  mbstring
  mysql
  pgsql
  redis
  soap
  sqlite3
  xml
  zip
)

packages=()
for version in 8.4 8.5; do
  for extension in "${extensions[@]}"; do
    packages+=("php${version}-${extension}")
  done
done
packages+=(php8.4-opcache)

apt-get update
apt-get install -y --no-install-recommends "${packages[@]}"

update-alternatives --set php /usr/bin/php8.5
update-alternatives --set phpize /usr/bin/phpize8.5
update-alternatives --set php-config /usr/bin/php-config8.5

installer_file="$(mktemp)"
trap 'rm -f "${key_file}" "${installer_file}"' EXIT
expected_signature="$(curl --fail --silent --show-error https://composer.github.io/installer.sig)"
curl --fail --silent --show-error https://getcomposer.org/installer --output "${installer_file}"
actual_signature="$(php -r "echo hash_file('sha384', '${installer_file}');")"

if [[ "${actual_signature}" != "${expected_signature}" ]]; then
  echo "Composer installer signature verification failed." >&2
  exit 1
fi

php "${installer_file}" \
  --install-dir=/usr/local/bin \
  --filename=composer \
  --version="${COMPOSER_VERSION}" \
  --quiet

composer --version
rm -rf /var/lib/apt/lists/*
