#!/usr/bin/env bash
set -euo pipefail

expected_extensions=(
  bcmath
  curl
  gd
  intl
  mbstring
  mysqli
  pdo_mysql
  pdo_pgsql
  pdo_sqlite
  redis
  soap
  xml
  zip
)

for version in 8.4 8.5; do
  "php${version}" --version | head -n 1
  loaded_extensions="$("php${version}" -m | tr '[:upper:]' '[:lower:]')"
  for extension in "${expected_extensions[@]}"; do
    if ! grep -qx "${extension}" <<< "${loaded_extensions}"; then
      echo "PHP ${version} is missing extension ${extension}." >&2
      exit 1
    fi
  done
  "php${version}" -r 'exit(extension_loaded("Zend OPcache") ? 0 : 1);'
done

use-php 8.4
php --version | head -n 1 | grep -q '^PHP 8\.4\.'
phpize --version | grep -q 'PHP Api Version'
php-config --version | grep -q '^8\.4\.'

use-php 8.5
php --version | head -n 1 | grep -q '^PHP 8\.5\.'
php-config --version | grep -q '^8\.5\.'

composer --version | grep -q 'Composer version 2\.10\.3'
node --version | grep -q '^v24\.20\.0$'
npm --version
playwright --version | grep -q 'Version 1\.62\.1'

if ! runuser --user runner -- test -w /ms-playwright; then
  echo "Playwright browser directory is not writable by the runner user." >&2
  exit 1
fi

if [[ "${SKIP_PLAYWRIGHT_LAUNCH:-false}" == "true" ]]; then
  if ! find /ms-playwright -type f -name headless_shell -perm -u=x -print -quit | grep -q .; then
    echo "Playwright Chromium headless shell is missing or not executable." >&2
    exit 1
  fi
else
  NODE_PATH="$(npm root --global)" node <<'NODE'
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.setContent('<title>runner-smoke</title>');
  if (await page.title() !== 'runner-smoke') {
    throw new Error('Unexpected page title');
  }
  await browser.close();
})();
NODE
fi

docker --version
rustfs --version
