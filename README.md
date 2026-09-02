# Docker GitHub Actions Runner

Dieses Repository baut einen organisationsunabhängigen GitHub Actions Runner für einen dedizierten Coolify-CI-Server. Die Compose-Konfiguration startet genau einen Organization Runner und authentifiziert ihn über eine GitHub App.

## Enthalten

- GitHub Actions Runner 2.337.0 auf Ubuntu 24.04
- PHP CLI 8.4 und 8.5, Composer 2.10.3 und übliche Web- und Datenbank-Extensions
- Node.js 24.20.0 LTS
- AWS CLI
- Playwright 1.62.1 mit Chromium
- RustFS 1.0.0-rc.4 für kurzlebige S3-Testinstanzen
- Docker CLI mit Zugriff auf den Docker-Daemon des CI-Hosts

Das Upstream-Image ist mit Version und Multi-Arch-Digest gepinnt. Runner-, Playwright-, Composer-, Node- und RustFS-Versionen werden bewusst über Pull Requests aktualisiert.

GitHub Actions baut und testet das Image separat für `linux/amd64` und `linux/arm64`. Nach einem erfolgreichen Push auf `main` veröffentlicht die Pipeline ein gemeinsames Multi-Arch-Image als `ghcr.io/bambamboole/github-runner:latest` und zusätzlich mit einem unveränderlichen `sha-<commit>`-Tag.

Zusätzlich kann Packer aus Ubuntu 24.04 einen privaten DigitalOcean-Snapshot für kurzlebige CI-Fab-Runner bauen. Dieses VM-Image ist derzeit AMD64, enthält AWS CLI 2.36.38 und stellt den Runner unter `/opt/actions-runner` für den Benutzer `runner` bereit.

## GitHub App anlegen

Lege in der Zielorganisation eine private GitHub App an. Sie benötigt auf Organisationsebene:

- `Self-hosted runners`: Read and write

Webhooks und Benutzerautorisierung werden nicht benötigt. Installiere die App in der Organisation, generiere einen privaten Schlüssel und notiere:

- den Login des Accounts, in dem die App installiert ist
- die App-ID
- den PEM-Schlüssel

Eine private App kann nur im Account ihres Eigentümers installiert werden.

### App über das Manifest-Script anlegen

Mit einer angemeldeten [GitHub CLI](https://cli.github.com/) kann das Repository die App-Konfiguration vorbereiten:

```bash
scripts/create-github-app example-org
```

Das Script öffnet den offiziellen GitHub-App-Manifest-Flow im Browser. Ein Organisations-Owner bestätigt dort die Erstellung und anschließend die Installation. Danach schreibt das Script Installations-Login, App-ID und den einmalig ausgegebenen privaten Schlüssel mit Dateimodus `0600` nach `.github-app.env` und gibt denselben Coolify-kompatiblen Variablenblock im Terminal aus.

Name und Ausgabepfad lassen sich anpassen:

```bash
scripts/create-github-app example-org \
  --name example-org-ci-runner \
  --output coolify-runner.env
```

Die Browser-Bestätigung ist von GitHub vorgeschrieben; `gh` übernimmt danach den API-Austausch des temporären Manifest-Codes. Bereits vorhandene Ausgabedateien werden nicht überschrieben.

## Lokal prüfen

Voraussetzung ist ein laufender Docker-Daemon.

```bash
make build
make test
```

Die Tests prüfen beide PHP-Versionen und Extensions, Composer und Node, einen echten Headless-Chromium-Start, den vollständigen RustFS-S3-Lifecycle und einen kurzlebigen Container über den gemounteten Docker-Socket. Im emulierten ARM64-CI-Job wird statt des unter QEMU nicht zuverlässig startenden Chromium-Prozesses die installierte ausführbare Browser-Binary geprüft; der echte Browser-Start bleibt im AMD64-Job verpflichtend.

## DigitalOcean-Image bauen

Das Repository-Secret `DIGITALOCEAN_TOKEN` muss einen DigitalOcean Personal Access Token mit Lese- und Schreibzugriff auf Droplets, Snapshots, Images, Tags und SSH-Keys enthalten. Danach lässt sich der Workflow `Build DigitalOcean runner image` manuell starten.

Der Workflow:

1. baut mit Packer aus `ubuntu-24-04-x64` einen Snapshot in `fra1`,
2. startet aus dem Snapshot ein neues Test-Droplet,
3. prüft den Image-Vertrag und alle installierten Werkzeuge einschließlich Chromium, RustFS und Docker,
4. löscht das Test-Droplet und den temporären SSH-Key wieder.

Der getestete Snapshot bleibt im DigitalOcean-Account erhalten. Seine ID steht in der Workflow-Zusammenfassung und kann in CI Fab als Runner-Image hinterlegt werden.

Mit lokal installiertem Packer 1.16.0 lässt sich die Vorlage ohne Cloud-Zugriff prüfen:

```bash
make packer-validate
```

Ein lokaler Build benötigt zusätzlich `doctl` und nutzt `DIGITALOCEAN_TOKEN` aus der Umgebung:

```bash
export DIGITALOCEAN_TOKEN=...
make packer-build
tests/digitalocean-snapshot-smoke.sh "$(jq -r '.builds[-1].artifact_id | split(":")[-1]' packer/manifest.json)"
```

## In Coolify deployen

1. Lege in Coolify eine Docker-Compose-Anwendung aus diesem Git-Repository an.
2. Hinterlege diese Variablen als Secrets beziehungsweise Laufzeitkonfiguration:

   ```text
   GITHUB_ORG_NAME
   GITHUB_APP_LOGIN
   GITHUB_APP_ID
   GITHUB_APP_PRIVATE_KEY
   ```

   `GITHUB_APP_LOGIN` ist beim Org-Runner der Organisations-Login und entspricht damit `GITHUB_ORG_NAME`. Der Upstream nutzt ihn, um die passende App-Installation zu finden.

3. Der PEM-Schlüssel kann mehrzeilig oder mit literalen `\n` gespeichert werden. Keine Anführungszeichen um den eigentlichen Wert ergänzen.
4. Optional können Name, Gruppe, Labels und Image gesetzt werden:

   ```text
   RUNNER_NAME
   RUNNER_GROUP
   RUNNER_LABELS
   RUNNER_IMAGE
   ```

5. Weise keine Domain zu. Die Anwendung veröffentlicht keine Ports.
6. Deploye die Compose-Anwendung und kontrolliere den Runner anschließend unter `Settings → Actions → Runners` in der Zielorganisation.

Coolify verwendet [`docker-compose.yml`](docker-compose.yml) als maßgebliche Konfiguration. Der Runner mountet `/var/run/docker.sock` und erhält dadurch Kontrolle über den CI-Host.

## Runner in Workflows verwenden

Die Standardlabels erlauben beispielsweise:

```yaml
jobs:
  test:
    runs-on: [self-hosted, ci, php-8.5]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: php --version
```

Weitere Labels sind `docker`, `php-8.4`, `playwright`, `chromium` und `rustfs`. Eigene Labels werden über `RUNNER_LABELS` als kommaseparierte Liste gesetzt.

### PHP auswählen

PHP 8.5 ist der Standard. Matrix-Jobs wählen ihre Version explizit:

```yaml
strategy:
  matrix:
    php: ['8.4', '8.5']

steps:
  - run: use-php "${{ matrix.php }}"
  - run: composer install --no-interaction --prefer-dist
```

### Chromium verwenden

Projekte sollten dieselbe Playwright-Version wie das Image verwenden, damit der vorinstallierte Browser passt:

```json
{
  "devDependencies": {
    "@playwright/test": "1.62.1"
  }
}
```

`PLAYWRIGHT_BROWSERS_PATH` ist bereits auf `/ms-playwright` gesetzt.

## RustFS für einen Job starten

`rustfs-ci` startet eine lokale, nicht persistente RustFS-Instanz, wartet auf Readiness und legt den gewünschten Bucket an. Zugangsdaten werden nur aus der Umgebung gelesen und nicht geloggt.

```yaml
jobs:
  s3-test:
    runs-on: [self-hosted, ci, rustfs]
    env:
      RUSTFS_ACCESS_KEY: ${{ secrets.CI_S3_ACCESS_KEY }}
      RUSTFS_SECRET_KEY: ${{ secrets.CI_S3_SECRET_KEY }}
      RUSTFS_BUCKET: test-bucket
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Start RustFS
        run: rustfs-ci start
      - name: Run tests
        run: vendor/bin/phpunit
        env:
          AWS_ENDPOINT_URL: ${{ env.RUSTFS_ENDPOINT }}
          AWS_ACCESS_KEY_ID: ${{ env.RUSTFS_ACCESS_KEY }}
          AWS_SECRET_ACCESS_KEY: ${{ env.RUSTFS_SECRET_KEY }}
          AWS_BUCKET: ${{ env.RUSTFS_BUCKET }}
          AWS_USE_PATH_STYLE_ENDPOINT: "true"
      - name: Stop RustFS
        if: always()
        run: rustfs-ci stop
```

Verfügbare Befehle:

```text
rustfs-ci start
rustfs-ci status
rustfs-ci stop
```

Direkte Jobprozesse erreichen RustFS unter `http://127.0.0.1:9000`. Ein mit dem Host-Daemon gestarteter Container besitzt einen eigenen Netzwerk-Namespace. Falls dieser Container RustFS benötigt, kann er den Netzwerk-Namespace des Runner-Containers teilen:

```bash
docker run --rm --network "container:$(hostname)" application-tests
```

## Sicherheit

Der Docker-Socket gewährt Workflows praktisch Root-Zugriff auf den gesamten CI-Server. Auf diesem Server dürfen deshalb keine Produktionsdienste oder unabhängigen Vertrauensbereiche liegen.

Nicht vertrauenswürdige Pull-Request-Jobs, insbesondere aus Forks öffentlicher Repositories, dürfen niemals diesen Self-hosted Runner verwenden. Solche Prüfungen laufen auf GitHub-hosted Runnern; der Self-hosted Runner bleibt auf geschützte Branches, vertrauenswürdige Tags und manuell gestartete Maintainer-Workflows begrenzt.

Runner-Gruppen sollten nur ausgewählten Repositories Zugriff geben. Docker-Caches, Images und Volumes benötigen zusätzlich Disk-Monitoring und eine regelmäßige CI-spezifische Bereinigung.

## Versionen aktualisieren

Ändere die Build-Argumente im [`Dockerfile`](Dockerfile) einzeln und führe danach `make build test` aus. Beim Runner-Basisimage müssen Tag und Multi-Arch-Digest gemeinsam aktualisiert werden. RustFS ist derzeit ein Release Candidate und ausschließlich als CI-Testwerkzeug vorgesehen.
