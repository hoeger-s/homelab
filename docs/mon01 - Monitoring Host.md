# mon01 - Monitoring Host

Stand: 26.10.2026


Zentrale Monitoring-Instanz des Homelabs. Trägt den kompletten Monitoring-Stack als Docker Compose (Prometheus, Alertmanager, Grafana, Loki, Alloy, PVE-Exporter, Node-Exporter) für sich selbst und `pve01`. `mon01` läuft rund um die Uhr und startet nach einem Stromausfall per BIOS-Einstellung wieder von selbst.

Das Monitoring läuft bewusst auf eigener Hardware und nicht als Container auf `pve01`. Sonst wäre bei einem Ausfall von `pve01` auch das Monitoring weg, genau dann, wenn man es braucht.


## 🖥️ Hardware

| Komponente | Hardware |
|---|---|
| Modell | Intel NUC7i5BNK (Mini-PC) |
| CPU | Intel Core i5-7260U |
| Kerne / Threads | 2 Kerne / 4 Threads |
| RAM | 16 GB DDR4-SO-DIMM |
| GPU | Iris Plus Graphics 640 |
| BIOS | Version 0080 (25.07.2019) |
| Systemlaufwerk | Kingston SSD UV500 240 GB M.2 SATA |
| Betriebssystem | Debian 13/Trixie |


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | eno1 |
| Hostname | mon01 |
| FQDN | mon01.internal |
| IP CIDR | 10.0.40.90/24 |
| Gateway | 10.0.40.1 |
| DNS | 10.0.40.1, ohne Suchdomäne |
| VLAN | Homelab (VLAN 40) |
| Switchport | Port 3, Profil Homelab-Access |
| Weboberfläche | Grafana `http://10.0.40.90:3000` bzw. `http://mon01.internal:3000` |

Die IP-Adresse ist fest auf dem Host eingetragen und wird nicht per DHCP vom UniFi-Gateway vergeben. So startet `mon01` auch dann mit seiner Adresse, wenn das Gateway gerade nicht antwortet. Eine zusätzliche Reservierung im Gateway gibt es bewusst nicht, damit die Adresse nur an einer Stelle gepflegt wird. Unter `mon01.internal` ist der Host per DNS-Eintrag im Gateway erreichbar.

`mon01` selbst spricht alle Ziele über ihre Adressen an und nicht über deren DNS-Namen. Eine Suchdomäne ist deshalb nicht gesetzt.


## 💾 Storage-Layout

Debian-Standard-Partitionierung, eine Partition für das gesamte System.
Der komplette Docker-Compose-Stack liegt unter `/opt/monitoring`. Die Daten von Prometheus, Grafana, Loki und dem Alertmanager liegen in Docker-Volumes unter `/var/lib/docker/volumes/`.

```bash
/opt/monitoring/
├── docker-compose.yml
├── .env                            # Grafana-Zugangsdaten, nicht im Repo (Vorlage .env.example)
├── prometheus/
│   ├── prometheus.yml
│   └── alert-rules.yml
├── alertmanager/alertmanager.yml
├── grafana/provisioning/           # Datenquellen Prometheus und Alertmanager
├── loki/loki-config.yml
├── alloy/config.alloy
└── pve-exporter/pve.yml            # enthält den PVE-API-Token, nicht im Repo (Vorlage pve.yml.example)
```

Konfiguration: [`configs/mon01/monitoring/`](../configs/mon01/monitoring/)


## 🔐 Hardening

- Separater Admin-User mit `sudo` und SSH-Key
- Root- und Passwort-Login per SSH deaktiviert
- Admin-User nicht in der `docker`-Gruppe, denn das entspräche `root`-Rechten. Alle `docker`-Befehle laufen mit `sudo`
- Eigener SSH-Schlüssel für die Host-Sicherung, der auf `pve01` Dateien nur per `scp` in einen Ordner ablegen darf, kein Shell-Zugriff
- PVE-Exporter mit nur lesendem API-Token (Rolle `PVEAuditor`, siehe [pve01 - Proxmox Host](pve01%20-%20Proxmox%20Host.md)), ohne SSL-Verifikation (`verify_ssl: false`), da `pve01` ein selbst signiertes Zertifikat hat
- Host-Firewall `ufw`, Default-Policy `deny` (Input), `allow` (Output), `deny` (Routed)
    - [`ufw-docker`](https://github.com/chaifeng/ufw-docker) installiert, siehe unten

**`ufw-docker`:** Docker schreibt die Port-Freigaben seiner Container direkt in die `FORWARD`-Kette von `iptables`. Normale `ufw`-Regeln greifen dort nicht. Jeder veröffentlichte Container-Port wäre trotz `ufw` offen. `ufw-docker` hängt sich davor und lässt nur durch, was per `ufw route allow` erlaubt ist. Die Ports nur an `127.0.0.1` zu binden, reicht hier nicht, da Grafana aus Trusted und Loki von `pve01` erreichbar sein müssen.

Die Vorlage von `ufw-docker` gibt alle privaten Netze pauschal frei (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`). Damit wirken die Regeln nur gegen Zugriffe aus dem Internet, nicht aus dem Heimnetz. In `/etc/ufw/after.rules` bleibt deshalb nur `172.16.0.0/12` freigegeben, das sind die Docker-Netze selbst. Ohne diese Zeile kämen Prometheus und PVE-Exporter nicht mehr an `pve01` heran.

**Regeln (`ufw`):**

| Direction | Action | Protocol | Port | Source | Zweck |
|---|---|---|---|---|---|
| in | ALLOW | tcp | 22 | 10.0.10.0/24 | SSH aus Trusted (im Gateway zusätzlich nur von der Workstation) |
| in | ALLOW | tcp | 3000 | 10.0.10.0/24 | Grafana aus Trusted |
| fwd | ALLOW | tcp | 3000 | 10.0.10.0/24 | Grafana, Docker-Port (`ufw route allow`) |
| in | ALLOW | tcp | 3100 | 10.0.99.10 | Logs von `pve01` an Loki |
| fwd | ALLOW | tcp | 3100 | 10.0.99.10 | Loki, Docker-Port (`ufw route allow`) |

Im Gateway kommen dazu die Regeln "Trusted zu mon01" (3000), "mon01 zu pve01" und "pve01 zu mon01", siehe [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md).

> Grafana (3000) und Loki (3100) sind die einzigen veröffentlichten Ports. Prometheus, Alertmanager, PVE-Exporter und Node-Exporter laufen nur im internen Docker-Netz und sind von außen nicht erreichbar. Prometheus ist deshalb nur über Grafana oder per `docker exec` einsehbar.


## 📊 Monitoring - Docker-Compose-Stack

Sieben Container unter `/opt/monitoring` (siehe Storage-Layout). Alle Images laufen auf `:latest`, siehe Offene Punkte.

| Container | Image | Port | Zweck |
|---|---|---|---|
| `prometheus` | `prom/prometheus` | 9090 (intern) | Metriken sammeln und speichern, Aufbewahrung 30 Tage |
| `alertmanager` | `prom/alertmanager` | 9093 (intern) | Alarme bündeln und weiterleiten |
| `node-exporter` | `prom/node-exporter` | 9100 (intern) | OS-Metriken von `mon01` |
| `grafana` | `grafana/grafana` | 3000 | Dashboards |
| `loki` | `grafana/loki` | 3100 | Logs speichern, Aufbewahrung 7 Tage |
| `alloy` | `grafana/alloy` | - (intern) | liest das Journal von `mon01` und schickt es an Loki |
| `pve-exporter` | `prompve/prometheus-pve-exporter` | 9221 (intern) | fragt die Proxmox-API von `pve01` ab |

Compose-Datei: [`configs/mon01/monitoring/docker-compose.yml`](../configs/mon01/monitoring/docker-compose.yml)

**Scrape-Ziele:**

| Job | `targets` | `instance` | Zweck |
|---|---|---|---|
| `prometheus` | `localhost:9090` | `mon01` | Selbstüberwachung |
| `node_exporter_mon01` | `node-exporter:9100` | `mon01` | OS-Metriken `mon01` |
| `node_exporter_pve01` | `10.0.99.10:9100` | `pve01` | OS-Metriken `pve01` |
| `pve_exporter` | `10.0.99.10` | `pve01` | Proxmox-API über `pve-exporter:9221` (Container, Storage-Pools) |
| `nvidia_gpu_pve01` | `10.0.99.10:9835` | `pve01` | GPU-Metriken `pve01` |

Jedes Ziel trägt den Hostnamen als `instance` statt der üblichen Kombination aus Adresse und Port. Alarmregeln und Dashboards beziehen sich nur auf diesen Namen. Ändert sich eine Adresse, wird nur die Zeile `targets` angepasst, die Verläufe laufen unter demselben Namen weiter.

Konfiguration: [`configs/mon01/monitoring/prometheus/`](../configs/mon01/monitoring/prometheus/)

**Alarm-Regeln (Prometheus-Regeldatei -> Alertmanager):**

| Alarm | Bedingung | Severity |
|---|---|---|
| `MonitoringDiskSpaceLow` | `mon01`: weniger als 15 % frei auf `/` für 10 min | warning |
| `NodeExporterPve01Down` | Node-Exporter von `pve01` seit 2 min nicht erreichbar | critical |
| `Pve01CpuHigh` | CPU von `pve01` über 85 % für 5 min | warning |
| `Pve01RamHigh` | RAM von `pve01` über 85 % für 5 min | warning |
| `Pve01GpuHigh` | GPU von `pve01` über 85 % für 5 min | warning |
| `Pve01StoragePoolFull` | ein Storage-Pool von `pve01` über 85 % für 10 min | warning |

> Der Alertmanager hat keinen Benachrichtigungskanal. Ausgelöste Alarme sind nur in Grafana und im Alertmanager selbst sichtbar.

**Dashboards in Grafana:**

- "Homelab Overview": CPU, RAM, GPU, Netzwerk, Temperaturen und Storage-Pools von `pve01`, Tabellen für Container und VMs, Uptime
- "Log Overview": Log-Volumen, Fehler-Rate und Suche über alle Logs, siehe unten

Die Dashboards liegen nur in der Datenbank von Grafana, nicht als Datei auf `mon01`. Die Fassungen im Repo sind Exporte. In Grafana kommen Prometheus und Alertmanager als Datenquellen per Provisioning-Datei, die Loki-Datenquelle ist von Hand angelegt.

Exporte: [`configs/mon01/monitoring/grafana/dashboards/`](../configs/mon01/monitoring/grafana/dashboards/)


## 📜 Logging (Loki & Alloy)

Alloy liefert die Logs von `pve01` und `mon01` an Loki. Loki speichert sie als Dateien im Docker-Volume `loki-data` und bewahrt sie 7 Tage auf. Auf `mon01` ist Alloy ein eigener Container und liest das Journal des Hosts (nur lesend). Auf `pve01` ist Alloy direkt auf dem Host installiert und schickt das Journal übers Netz an Loki.

Alloy vergibt auf beiden Hosts dieselben Labels: `host` (`mon01`, `pve01`), `job` (`systemd-journal`), `unit` (z. B. `docker.service`) und `level` (Schweregrad aus dem Journal: `info`, `notice`, `warning`, `error` ...). Warum nur diese vier und wie sie technisch gesetzt werden, steht in [pve01 - Proxmox Host](pve01%20-%20Proxmox%20Host.md#-logging-alloy).

**Dashboard "Log Overview":**

- Log-Volumen über Zeit, je Host
- Fehler-Rate: zählt alle Einträge mit Schweregrad `error` und schlimmer
- Suche über alle Logs mit Filter nach Host

Abfrage der Fehler-Rate (LogQL):

```logql
sum by (host) (count_over_time({job="systemd-journal", level=~"emerg|alert|crit|error"} [$__interval]))
```

Gezählt wird über das Label `level`, nicht per Textsuche nach "error", "failed" oder "critical" in den Logzeilen. Eine Textsuche würde auch harmlose Zeilen mitzählen, die zufällig eines dieser Wörter enthalten. So zählt nur, was das System selbst als Fehler einstuft. Warnungen gehören bei Bedarf in ein eigenes Panel, nicht in die Fehlerkurve.

Konfiguration: [`configs/mon01/monitoring/alloy/config.alloy`](../configs/mon01/monitoring/alloy/config.alloy), [`configs/mon01/monitoring/loki/loki-config.yml`](../configs/mon01/monitoring/loki/loki-config.yml)

> Alloy auf `mon01` schickt die Logs im internen Docker-Netz an Loki, dafür ist keine Firewall-Regel nötig.


## 💾 Backup

`mon01` hat nur eine Platte. Die Sicherung landet deshalb auf `pve01` in `hdd-backup`, nicht lokal.

- **Zeitplan:** Skript mit systemd-Timer, jeden Tag 02:30 Uhr. War `mon01` zu der Zeit aus, wird die Sicherung beim nächsten Start nachgeholt
- **Gesichert werden:**
    - `/etc` komplett (inkl. `/etc/ufw` mit den Regeln für `ufw-docker`)
    - `/opt/monitoring` mit allen Konfigurationen des Stacks
    - eigene Skripte, darunter das Sicherungsskript selbst
    - die SSH-Schlüssel von `root` und Admin-User
    - die Daten von Grafana (Docker-Volume) mit Dashboards, Benutzern und der Loki-Datenquelle
    - eine Liste aller installierten Pakete, `ufw status`, die laufenden Container und die genauen Image-Stände. Solange die Images auf `:latest` laufen, lässt sich so nach einer Wiederherstellung gezielt die vorherige Version holen
- **Nicht gesichert:**
    - Grafana-Plugins, nur ihre Liste. Grafana lädt sie selbst nach. Mit Plugins wäre das Archiv rund 168 MB groß, ohne sind es rund 570 KB
    - Messwerte von Prometheus und Logs aus Loki

Dateien: [`configs/mon01/host-backup/`](../configs/mon01/host-backup/)

Ablauf und Wiederherstellung: [Backup & Wiederherstellung](Backup%20&%20Wiederherstellung.md)


## 📝 Offene Punkte

- Benachrichtigungskanal für den Alertmanager, dazu Testalarme
- Alarm, wenn eine Sicherung fehlschlägt oder zu alt ist
- Selbstüberwachung von `mon01` ausbauen (CPU, RAM, Zustand der Container) und eine Meldung von außen, wenn `mon01` ganz ausfällt
- `proxy01` und `cal01` mit Dienst-Prüfung überwachen (Blackbox-Exporter)
- Docker-Images auf feste Versionen pinnen statt `:latest`
- Grafana hinter den Reverse Proxy
- `verify_ssl: false` beim PVE-Exporter ablösen, sobald es eine interne CA gibt
- Loki meldet dauerhaft "Ingester not ready", obwohl Logs ankommen. Ursache klären
- Ausstehende Updates einspielen
- Ziele über DNS-Namen statt Adressen ansprechen (Prometheus, Backup-Skript, Alloy auf `pve01`)
