#!/usr/bin/env bash
set -euo pipefail

readonly PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:?PLAYWRIGHT_VERSION is required}"
readonly PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/ms-playwright}"

mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"
npm install --global --no-audit --no-fund "playwright@${PLAYWRIGHT_VERSION}"
playwright install --with-deps chromium

chmod -R a+rX "${PLAYWRIGHT_BROWSERS_PATH}"
npm cache clean --force
rm -rf /var/lib/apt/lists/*
