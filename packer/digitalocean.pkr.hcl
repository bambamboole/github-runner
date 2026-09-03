packer {
  required_version = "= 1.16.0"

  required_plugins {
    digitalocean = {
      source  = "github.com/digitalocean/digitalocean"
      version = "= 1.4.1"
    }
  }
}

variable "build_region" {
  type    = string
  default = "fra1"
}

variable "build_size" {
  type    = string
  default = "s-1vcpu-1gb"
}

variable "aws_cli_version" {
  type    = string
  default = "2.36.38"
}

variable "composer_version" {
  type    = string
  default = "2.10.3"
}

variable "node_version" {
  type    = string
  default = "24.20.0"
}

variable "playwright_version" {
  type    = string
  default = "1.62.1"
}

variable "runner_checksum" {
  type    = string
  default = "70920811a4f8ad4328818682bca5c6469c1c942fab52448868071d0063816613"
}

variable "runner_version" {
  type    = string
  default = "2.337.0"
}

variable "rustfs_version" {
  type    = string
  default = "1.0.0-rc.4"
}

variable "yq_checksum" {
  type    = string
  default = "fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4"
}

variable "yq_version" {
  type    = string
  default = "4.53.3"
}

variable "snapshot_name" {
  type    = string
  default = ""
}

variable "ssh_key_id" {
  type    = number
  default = 0
}

variable "ssh_private_key_file" {
  type      = string
  default   = ""
  sensitive = true
}

variable "source_image" {
  type    = string
  default = "ubuntu-24-04-x64"
}

locals {
  snapshot_name = var.snapshot_name != "" ? var.snapshot_name : "ci-fab-runner-${var.runner_version}-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
}

source "digitalocean" "runner" {
  image                = var.source_image
  region               = var.build_region
  size                 = var.build_size
  ssh_key_id           = var.ssh_key_id
  ssh_private_key_file = var.ssh_private_key_file
  ssh_username         = "root"
  snapshot_name        = local.snapshot_name
  snapshot_tags        = ["ci-fab-runner"]
  droplet_name         = "packer-${local.snapshot_name}"
  droplet_agent        = false
  state_timeout        = "10m"
  snapshot_timeout     = "90m"
}

build {
  sources = ["source.digitalocean.runner"]

  provisioner "shell" {
    script = "packer/scripts/prepare.sh"
  }

  provisioner "file" {
    source      = "scripts/install-aws-cli.sh"
    destination = "/tmp/install-aws-cli.sh"
  }

  provisioner "file" {
    source      = "scripts/install-node.sh"
    destination = "/tmp/install-node.sh"
  }

  provisioner "file" {
    source      = "scripts/install-php.sh"
    destination = "/tmp/install-php.sh"
  }

  provisioner "file" {
    source      = "scripts/install-playwright.sh"
    destination = "/tmp/install-playwright.sh"
  }

  provisioner "file" {
    source      = "scripts/install-rustfs.sh"
    destination = "/tmp/install-rustfs.sh"
  }

  provisioner "file" {
    source      = "scripts/rustfs-ci"
    destination = "/tmp/rustfs-ci"
  }

  provisioner "file" {
    source      = "scripts/use-php"
    destination = "/tmp/use-php"
  }

  provisioner "shell" {
    environment_vars = [
      "AWS_CLI_VERSION=${var.aws_cli_version}",
      "COMPOSER_VERSION=${var.composer_version}",
      "NODE_VERSION=${var.node_version}",
      "PLAYWRIGHT_VERSION=${var.playwright_version}",
      "RUNNER_CHECKSUM=${var.runner_checksum}",
      "RUNNER_VERSION=${var.runner_version}",
      "RUSTFS_VERSION=${var.rustfs_version}",
      "YQ_CHECKSUM=${var.yq_checksum}",
      "YQ_VERSION=${var.yq_version}",
    ]
    script = "packer/scripts/install.sh"
  }

  provisioner "file" {
    source      = "tests/docker-smoke.sh"
    destination = "/tmp/docker-smoke.sh"
  }

  provisioner "file" {
    source      = "tests/rustfs-smoke.sh"
    destination = "/tmp/rustfs-smoke.sh"
  }

  provisioner "file" {
    source      = "tests/smoke.sh"
    destination = "/tmp/smoke.sh"
  }

  provisioner "file" {
    source      = "tests/vm-smoke.sh"
    destination = "/tmp/vm-smoke.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod 0755 /tmp/docker-smoke.sh /tmp/rustfs-smoke.sh /tmp/smoke.sh /tmp/vm-smoke.sh",
      "/tmp/vm-smoke.sh",
    ]
  }

  provisioner "shell" {
    script = "packer/scripts/finalize.sh"
  }

  post-processor "manifest" {
    output     = "packer/manifest.json"
    strip_path = true
  }
}
