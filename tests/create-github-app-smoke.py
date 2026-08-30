#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import runpy
import tempfile
import threading
import urllib.request
from pathlib import Path


script = runpy.run_path("scripts/create-github-app")
ManifestHandler = script["ManifestHandler"]
ManifestServer = script["ManifestServer"]
validate_args = script["validate_args"]
write_credentials = script["write_credentials"]


with tempfile.TemporaryDirectory() as temporary_directory:
    root = Path(temporary_directory)
    output = root / "credentials.env"
    args = argparse.Namespace(
        organization="example-org",
        timeout=30,
        output=output,
        homepage="https://example.com/runner",
        name=None,
    )
    assert validate_args(args) == "example-org-ci-runner"

    credentials = write_credentials(
        output,
        "example-org",
        {
            "id": 123456,
            "slug": "example-org-ci-runner",
            "pem": "-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n",
        },
    )
    expected_credentials = (
        "GITHUB_ORG_NAME=example-org\n"
        "GITHUB_APP_LOGIN=example-org\n"
        "GITHUB_APP_ID=123456\n"
        "GITHUB_APP_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\\nsecret\\n"
        "-----END PRIVATE KEY-----\n"
    )
    assert credentials == expected_credentials
    assert output.read_text(encoding="utf-8") == expected_credentials
    assert os.stat(output).st_mode & 0o777 == 0o600

server = ManifestServer(("127.0.0.1", 0), ManifestHandler)
server.state_token = "expected-state"
server.manifest = (
    '{"default_permissions":{"organization_self_hosted_runners":"write"}}'
)
server.github_url = "https://github.com/organizations/example-org/settings/apps/new"
server.callback_code = None
server.callback_event = threading.Event()
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()

try:
    port = server.server_address[1]
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=5) as response:
        form = response.read().decode("utf-8")
    assert 'method="post"' in form
    assert "organization_self_hosted_runners" in form

    callback = (
        f"http://127.0.0.1:{port}/callback"
        "?state=expected-state&code=temporary-code"
    )
    with urllib.request.urlopen(callback, timeout=5) as response:
        assert response.status == 200
    assert server.callback_event.wait(1)
    assert server.callback_code == "temporary-code"
finally:
    server.shutdown()
    server.server_close()
