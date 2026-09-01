# syntax=docker/dockerfile:1.7

ARG RUNNER_BASE_IMAGE="ghcr.io/myoung34/docker-github-actions-runner:2.337.0-ubuntu-noble@sha256:1b947d2475cc6f4c3edf0e91dd879b091857e41a311be917016243479bb34101"
FROM ${RUNNER_BASE_IMAGE}

ARG TARGETARCH
ARG COMPOSER_VERSION="2.10.3"
ARG NODE_VERSION="24.20.0"
ARG PLAYWRIGHT_VERSION="1.62.1"
ARG RUSTFS_VERSION="1.0.0-rc.4"

ENV PLAYWRIGHT_BROWSERS_PATH="/ms-playwright" \
    RUNNER_TOOL_CACHE="/opt/hostedtoolcache"

COPY --chmod=755 scripts/install-php.sh /usr/local/src/install-php.sh
COPY --chmod=755 scripts/install-node.sh /usr/local/src/install-node.sh
COPY --chmod=755 scripts/install-playwright.sh /usr/local/src/install-playwright.sh
COPY --chmod=755 scripts/install-rustfs.sh /usr/local/src/install-rustfs.sh

RUN COMPOSER_VERSION="${COMPOSER_VERSION}" /usr/local/src/install-php.sh \
    && NODE_VERSION="${NODE_VERSION}" TARGETARCH="${TARGETARCH}" RUNNER_TOOL_CACHE="${RUNNER_TOOL_CACHE}" /usr/local/src/install-node.sh \
    && PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION}" /usr/local/src/install-playwright.sh \
    && RUSTFS_VERSION="${RUSTFS_VERSION}" TARGETARCH="${TARGETARCH}" /usr/local/src/install-rustfs.sh \
    && rm -f \
        /usr/local/src/install-php.sh \
        /usr/local/src/install-node.sh \
        /usr/local/src/install-playwright.sh \
        /usr/local/src/install-rustfs.sh

COPY --chmod=755 scripts/use-php /usr/local/bin/use-php
COPY --chmod=755 scripts/rustfs-ci /usr/local/bin/rustfs-ci

LABEL org.opencontainers.image.title="GitHub Actions Runner" \
      org.opencontainers.image.description="GitHub Actions runner with PHP 8.4/8.5, Chromium, Playwright and RustFS" \
      org.opencontainers.image.source="https://github.com/bambamboole/github-runner"
