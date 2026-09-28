# mon01 - Monitoring Host

Stand: 28.09.2026


Zentrale Monitoring-Instanz des Homelabs, trägt den kompletten Docker-Compose-basierten Monitoring-Stack (Prometheus, Grafana, Loki, Alloy, PVE-Exporter, Alertmanager, Node-Exporter) für sich selbst und `pve01`.


## 🖥️ Hardware

**Intel NUC7i5BNK (Mini-PC)**

| Komponente | Hardware |
|---|---|
| CPU | Intel Core i5-7260U |
| Kerne / Threads | 2 Kerne / 4 Threads |
| RAM | 16 GB DDR4-SO-DIMM |
| GPU | Iris Plus Graphics 640 |
| Mainboard | N/A |
| BIOS | BNKBL357.86A.0080.2019.0725.1139 |
| BIOS-Datum | 25-07-2019 |
| Systemlaufwerk | 240 GB SSD |
| Betriebssystem | Debian 13 |


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | eno1 |
| Hostname | mon01 |
| FQDN | mon01.stefan.lab |
| IP CIDR | 10.0.40.11/24 |
| Gateway | 10.0.40.1 |
| DNS | 10.0.40.1 |
| VLAN | Homelab-VLAN (10.0.40.0/24) |


## 💾 Storage-Layout

Debian-Standard-Partitionierung, eine Partition für das gesamte System.
Der komplette Docker-Compose-Stack (Configs, Compose-Datei, Datenverzeichnisse für Prometheus/Grafana/Loki/Alertmanager) liegt unter `/opt/monitoring`.

```bash
/opt/monitoring/
├── docker-compose.yml
├── .env                            # Grafana-Zugangsdaten, nicht committen
├── prometheus/
│   ├── prometheus.yml
│   └── alert-rules.yml
├── grafana/provisioning/           # Datenquellen (Prometheus, Alertmanager), Dashboards
├── loki/loki-config.yml
├── alloy/config.alloy
├── pve-exporter/pve.yml            # enthält PVE-API-Token, nicht committen
└── alertmanager/alertmanager.yml
```


## 🔐 Hardening

- Separaten Admin-User mit `sudo`-Rechten und SSH-Key-Auth angelegt
- Root-SSH-Login und Passwort-Auth deaktiviert
- Host-Firewall über `ufw`, Default-Policy `deny` (Input), `allow` (Output)
- [`ufw-docker`-Fix](https://github.com/chaifeng/ufw-docker) installiert:
    Docker schreibt Container-Port-Freigaben direkt in die `iptables`/`nftables`-`FORWARD`-Kette, normale `ufw allow`-Regeln wirken darauf nicht.
    Ohne den Fix wäre jeder veröffentlichte Container-Port trotz `ufw` erreichbar. Alternative wäre gewesen, die Ports nur an `127.0.0.1` zu binden statt sie über `ufw-docker` abzusichern. Weil Grafana (Trusted-VLAN) und Loki (`pve01`) aber beide über die externe Schnittstelle erreichbar sein müssen, fiel diese hier raus.
- Kein Beitritt zur `docker`-Gruppe (quasi Root-Rechte). Alle `docker`/`docker compose`-Befehle laufen mit `sudo`
- Dedizierter, auf `scp` beschränkter SSH-Key für die Backup-Übertragung auf `pve01` (kein Shell-Zugriff)
- PVE-Exporter:
    - Verbindung ohne SSL-Verifikation (`verify_ssl: false`), da `pve01`s Zertifikat selbstsigniert ist.


| Direction | Action | Protocol | Port | Source | Zweck |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 22 | 10.0.10.0/24 | SSH nur aus Trusted-VLAN (Admin) |
| in | ACCEPT | tcp | 3000 | 10.0.10.0/24 | Grafana-Dashboard nur aus Trusted-VLAN |
| in | ACCEPT | tcp | 3100 | 10.0.40.10/32 | Log-Push von `pve01`s Alloy-Instanz |

> Grafana (3000) und Loki (3100) sind Docker-veröffentlichte Ports, dafür zusätzlich zur normalen `ufw`-Regel eine `ufw route allow`-Regel nötig (siehe `ufw-docker`-Fix oben). Alle anderen Dienste (Prometheus, Alertmanager, PVE-Exporter, Node-Exporter) haben keinen veröffentlichten Port, laufen nur intern im Docker-Netzwerk.


## 📊 Monitoring - Docker-Compose-Stack

Docker-Compose-Stack mit sieben Containern unter `/opt/monitoring` (siehe Storage-Layout). Alle Images laufen aktuell auf `:latest`, nicht versionsgepinnt (siehe Offene Punkte).

| Container | Image | Port | Zweck |
|---|---|---|---|
| `prometheus` | `prom/prometheus:latest` | 9090 (intern) | Metriken-Sammlung/-Speicherung, Retention 30 Tage |
| `node-exporter` | `prom/node-exporter:latest` | 9100 (intern) | `mon01`-eigene OS-Metriken |
| `grafana` | `grafana/grafana:latest` | 3000 | Dashboards |
| `loki` | `grafana/loki:latest` | 3100 | Log-Speicherung, Retention 7 Tage |
| `alloy` | `grafana/alloy:latest` | - (intern) | liest `mon01`s systemd-Journal, pusht an Loki |
| `pve-exporter` | `prompve/prometheus-pve-exporter:latest` | 9221 (intern) | fragt `pve01`s Proxmox-API ab |
| `alertmanager` | `prom/alertmanager:latest` | 9093 (intern) | verarbeitet Alerts, aktuell ohne Notification-Kanal |


**Scrape-Ziele:**

| Job | Ziel | Zweck |
|---|---|---|
| `prometheus` | `localhost:9090` | Selbstüberwachung |
| `node_exporter_mon01` | `node-exporter:9100` | `mon01`-OS-Metriken |
| `node_exporter_pve01` | `10.0.40.10:9100` | `pve01`-OS-Metriken (nativ) |
| `pve_exporter` | `10.0.40.10` über `pve-exporter:9221` | `pve01`-Proxmox-API (VM-/Storage-Status) |
| `nvidia_gpu_pve01` | `10.0.40.10:9835` | `pve01`-GPU-Metriken (nativ) |


**Alert-Regeln** (Prometheus-Regeldatei -> Alertmanager)

| Alert | Bedingung | Severity |
|---|---|---|
| `MonitoringDiskSpaceLow` | `mon01`: freier Speicher auf `/` < 15% für 10 min | warning |
| `NodeExporterPve01Down` | `pve01`-Node-Exporter seit 2 min nicht erreichbar | critical |
| `Pve01CpuHigh` | `pve01`-CPU-Auslastung > 85% für 5 min | warning |
| `Pve01RamHigh` | `pve01`-RAM-Auslastung > 85% für 5 min | warning |
| `Pve01GpuHigh` | `pve01`-GPU-Auslastung > 85% für 5 min | warning |
| `Pve01StoragePoolFull` | ein `pve01`-Storage-Pool > 85% belegt für 10 min | warning |

**Dashboards in Grafana:**
- "Homelab Overview" (CPU/GPU/Memory/Storage/Network für `pve01`, VM-/LXC-Tabellen, System Health, Storage Pools)
- "Log Overview" (Loki/Alloy, siehe Logging unten)
- Eigenes Self-Monitoring-Dashboard für `mon01` selbst steht noch aus, siehe Offene Punkte


## 📜 Logging (Loki & Alloy)

Loki läuft als Docker-Container (Filesystem-Storage, Retention 7 Tage), erreichbar intern über `loki` bzw. für `pve01` extern über Port 3100. `mon01`s eigenes systemd-Journal wird von einer lokalen Alloy-Instanz gelesen und an Loki gepusht. `pve01`s Journal kommt zusätzlich von dessen **nativer** Alloy-Instanz übers Netz rein (siehe [pve01 - Proxmox Host](pve01%20-%20Proxmox%20Host.md)).

> Job-Label `systemd-journal` wird bei beiden Alloy-Instanzen per `loki.relabel` erzwungen, sonst überschreibt Alloy es automatisch mit dem Component-Namen.

Bekannte Labels: `host` (`mon01`/`pve01`), `job` (`systemd-journal`).

**Dashboard "Log Overview"** (Grafana, LogQL):
- Log-Volumen über Zeit
- Fehler-Rate (Text-Regex `(?i)error|failed|critical` auf den Logzeilen, keine echte Log-Level-Klassifizierung)
- Quick-Search mit `$host`-Filter-Variable


## 💾 Backup

Da `mon01` nur eine Festplatte besitzt, landen Config-Backups auf `pve01`s `hdd-backup`-Storage statt lokal. Zugriff läuft über den dedizierten, auf `scp` beschränkten SSH-Key (siehe oben Hardening).

**Gesichert:** `/etc/network/interfaces`, `/etc/resolv.conf`, `/etc/ssh/sshd_config`, `ufw status verbose`-Ausgabe, sowie der komplette `/opt/monitoring`-Ordner.

```bash
scp -O -i ~/.ssh/pve01-backup /tmp/mon01-config_<datum>.tar.gz <admin-user>@10.0.40.10:/mnt/hdd-storage/host-backups/
```

> Seit OpenSSH 9 nutzt `scp` standardmäßig SFTP statt des alten SCP-Protokolls.
> Der eingeschränkte Key erzwingt aber das alte Protokoll. Ohne das Flag -O hängt sich die Übertragung wortlos auf.

**Restore:** Archiv in ein Temp-Verzeichnis entpacken, benötigte Dateien gezielt zurückkopieren, bei `sshd_config`/`interfaces` danach den jeweiligen Dienst neu starten (`systemctl restart` `sshd`/`networking`). `ufw`-Regeln haben keinen 1:1-Restore-Mechanismus, müssen im Zweifel aus der mitgesicherten `ufw-status.txt` von Hand nachgezogen werden.


## 📝 Offene Punkte

- `verify_ssl: false` beim PVE-Exporter ablösen: Proxmox-API über `proxy01` mit gültigem Zertifikat ansprechen statt eigener CA
- Docker-Image-Versionen pinnen statt `:latest`
- Eigenes Self-Monitoring-Dashboard für `mon01` bauen
- Zusätzliche Log-Quellen erschließen (Proxmox-Task-Logs, Anwendungslogs)
- Log-Alerts einrichten
- Loki-Retention (7 Tage) einmal über einen vollen Zyklus verifizieren
- Alertmanager-Notification-Kanal einrichten (evtl. dedizierte E-Mail anlegen)
