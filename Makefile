IMAGE ?= github-runner:local
SKIP_PLAYWRIGHT_LAUNCH ?= false

.PHONY: build compose-config lint packer-build packer-init packer-validate test test-docker test-image test-rustfs

build:
	docker build --tag $(IMAGE) .

compose-config:
	docker compose --env-file .env.example config --quiet

lint:
	bash -n packer/scripts/*.sh scripts/*.sh scripts/rustfs-ci scripts/use-php tests/*.sh
	python3 scripts/create-github-app --help >/dev/null
	python3 tests/create-github-app-smoke.py
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck packer/scripts/*.sh scripts/*.sh scripts/rustfs-ci scripts/use-php tests/*.sh; fi

packer-init:
	packer init packer/digitalocean.pkr.hcl

packer-validate: packer-init
	packer fmt -check packer/digitalocean.pkr.hcl
	DIGITALOCEAN_TOKEN="$${DIGITALOCEAN_TOKEN:-validation-token}" packer validate packer/digitalocean.pkr.hcl

packer-build: packer-init
	scripts/build-digitalocean-image.sh

test-image:
	docker run --rm --shm-size=2g \
		--entrypoint /bin/bash \
		--env SKIP_PLAYWRIGHT_LAUNCH="$(SKIP_PLAYWRIGHT_LAUNCH)" \
		--volume "$(CURDIR)/tests:/tests:ro" \
		$(IMAGE) /tests/smoke.sh

test-rustfs:
	docker run --rm \
		--entrypoint /bin/bash \
		--volume "$(CURDIR)/tests:/tests:ro" \
		$(IMAGE) /tests/rustfs-smoke.sh

test-docker:
	docker run --rm \
		--entrypoint /bin/bash \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		--volume "$(CURDIR)/tests:/tests:ro" \
		$(IMAGE) /tests/docker-smoke.sh

test: lint compose-config test-image test-rustfs test-docker
