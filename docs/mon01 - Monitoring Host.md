# mon01 - Monitoring Host

Stand: 18.11.2026


Zentrale Monitoring-Instanz des Homelabs. Trägt den kompletten Monitoring-Stack als Docker Compose (Prometheus, Alertmanager, ntfy, Grafana, Loki, Alloy, PVE-Exporter, Node-Exporter) für sich selbst und `pve01`. `mon01` läuft rund um die Uhr und startet nach einem Stromausfall per BIOS-Einstellung wieder von selbst.

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
| Weboberfläche | Grafana `http://10.0.40.90:3000` bzw. `http://mon01.internal:3000`, ntfy `https://ntfy.home.<domain>` über `proxy01` |

Die IP-Adresse ist fest auf dem Host eingetragen und wird nicht per DHCP vom UniFi-Gateway vergeben. So startet `mon01` auch dann mit seiner Adresse, wenn das Gateway gerade nicht antwortet. Eine zusätzliche Reservierung im Gateway gibt es bewusst nicht, damit die Adresse nur an einer Stelle gepflegt wird. Unter `mon01.internal` ist der Host per DNS-Eintrag im Gateway erreichbar.

`mon01` selbst spricht alle Ziele über ihre Adressen an und nicht über deren DNS-Namen. Eine Suchdomäne ist deshalb nicht gesetzt.


## 💾 Storage-Layout

Debian-Standard-Partitionierung, eine Partition für das gesamte System.
Der komplette Docker-Compose-Stack liegt unter `/opt/monitoring`. Die Daten von Prometheus, Grafana, Loki und dem Alertmanager sowie der Nachrichten-Cache von ntfy liegen in Docker-Volumes unter `/var/lib/docker/volumes/`. Benutzer und Rechte von ntfy liegen dagegen unter `/opt/monitoring/ntfy/data/` und damit in der Host-Sicherung.

```bash
/opt/monitoring/
├── docker-compose.yml
├── .env                            # Grafana-Zugangsdaten, nicht im Repo (Vorlage .env.example)
├── prometheus/
│   ├── prometheus.yml
│   └── alert-rules.yml
├── alertmanager/
│   ├── alertmanager.yml
│   └── ntfy-token                  # Token für ntfy, nicht im Repo (Vorlage ntfy-token.example)
├── ntfy/
│   ├── server.yml
│   └── data/user.db                # Benutzer, Rechte und Tokens von ntfy, nicht im Repo
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
- Sicherheitsupdates automatisch, siehe unten

**`ufw-docker`:** Docker schreibt die Port-Freigaben seiner Container direkt in die `FORWARD`-Kette von `iptables`. Normale `ufw`-Regeln greifen dort nicht. Jeder veröffentlichte Container-Port wäre trotz `ufw` offen. `ufw-docker` hängt sich davor und lässt nur durch, was per `ufw route allow` erlaubt ist. Die Ports nur an `127.0.0.1` zu binden, reicht hier nicht, da Grafana aus Trusted und Loki von `pve01` und ntfy von `proxy01` erreichbar sein müssen.

Die Vorlage von `ufw-docker` gibt alle privaten Netze pauschal frei (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`). Damit wirken die Regeln nur gegen Zugriffe aus dem Internet, nicht aus dem Heimnetz. In `/etc/ufw/after.rules` bleibt deshalb nur `172.16.0.0/12` freigegeben, das sind die Docker-Netze selbst. Ohne diese Zeile kämen Prometheus und PVE-Exporter nicht mehr an `pve01` heran.

Konfiguration: [`configs/mon01/ufw/`](../configs/mon01/ufw/)

**Regeln (`ufw`):**

| Direction | Action | Protocol | Port | Source | Zweck |
|---|---|---|---|---|---|
| in | ALLOW | tcp | 22 | 10.0.10.0/24 | SSH aus Trusted (im Gateway zusätzlich nur von der Workstation) |
| fwd | ALLOW | tcp | 3000 | 10.0.10.0/24 | Grafana aus Trusted |
| fwd | ALLOW | tcp | 3100 | 10.0.99.10 | Logs von `pve01` an Loki |
| fwd | ALLOW | tcp | 2586 | 10.0.40.10 | ntfy, nur für `proxy01` |

Im Gateway kommen dazu die Regeln "Trusted zu mon01" (3000), "mon01 zu pve01" und "pve01 zu mon01", siehe [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md).

> Grafana (3000) und Loki (3100) und ntfy (2586) sind die einzigen veröffentlichten Ports. Prometheus, Alertmanager, PVE-Exporter und Node-Exporter laufen nur im internen Docker-Netz und sind von außen nicht erreichbar. Prometheus ist deshalb nur über Grafana oder per `docker exec` einsehbar.

**Automatische Updates:** `unattended-upgrades` spielt jeden Morgen um 05:00 die Sicherheitsupdates von Debian ein (nur aus `trixie-security`). Das liegt nach der Host-Sicherung um 02:30, der Stand direkt vor dem Update ist also immer gesichert. Danach startet `needrestart` die Dienste neu, die noch die alten Bibliotheken geladen haben. Kommt ein neuer Kernel, startet `mon01` direkt nach dem Update selbst neu, die Container des Stacks kommen danach von allein wieder hoch. Docker stammt aus dem Docker-Repo und bleibt, genau wie die Images des Stacks, außen vor. Beides und alle übrigen Updates kommen von Hand am monatlichen Patchday, siehe [Updates & Patchmanagement](Updates%20&%20Patchmanagement.md).

Konfiguration: [`configs/mon01/auto-updates/`](../configs/mon01/auto-updates/)


## 📊 Monitoring - Docker-Compose-Stack

Acht Container unter `/opt/monitoring` (siehe Storage-Layout). Jedes Image läuft mit einer festen Version, die in der Compose-Datei steht. So holt `docker compose pull` nie ungeplant eine neue Version. Außerdem ist jederzeit nachvollziehbar, was läuft. Neue Versionen werden nur von Hand eingetragen.

| Container | Image | Port | Zweck |
|---|---|---|---|
| `prometheus` | `prom/prometheus` | 9090 (intern) | Metriken sammeln und speichern, Aufbewahrung 30 Tage |
| `alertmanager` | `prom/alertmanager` | 9093 (intern) | Alerts bündeln und weiterleiten |
| `ntfy` | `binwiederhier/ntfy` | 2586 | Push-Benachrichtigungen, siehe unten |
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

Jedes Ziel trägt den Hostnamen als `instance` statt der üblichen Kombination aus Adresse und Port. Alert-Regeln und Dashboards beziehen sich nur auf diesen Namen. Ändert sich eine Adresse, wird nur die Zeile `targets` angepasst, die Verläufe laufen unter demselben Namen weiter.

Konfiguration: [`configs/mon01/monitoring/prometheus/`](../configs/mon01/monitoring/prometheus/)

**Alert-Regeln (Prometheus-Regeldatei -> Alertmanager):**

| Alert | Bedingung | Severity |
|---|---|---|
| `MonitoringDiskSpaceLow` | `mon01`: weniger als 15 % frei auf `/` für 10 min | warning |
| `NodeExporterPve01Down` | Node-Exporter von `pve01` seit 2 min nicht erreichbar | critical |
| `Pve01CpuHigh` | CPU von `pve01` über 85 % für 5 min | warning |
| `Pve01RamHigh` | RAM von `pve01` über 85 % für 5 min | warning |
| `Pve01GpuHigh` | GPU von `pve01` über 85 % für 5 min | warning |
| `Pve01StoragePoolFull` | ein Storage-Pool von `pve01` über 85 % für 10 min | warning |

> Ausgelöste Alerts schickt der Alertmanager an ntfy, siehe Benachrichtigungen.

**Dashboards in Grafana:**

- "Homelab Overview": CPU, RAM, GPU, Netzwerk, Temperaturen und Storage-Pools von `pve01`, Tabellen für Container und VMs, Uptime
- "Log Overview": Log-Volumen, Fehler-Rate und Suche über alle Logs, siehe unten

Die Dashboards liegen nur in der Datenbank von Grafana, nicht als Datei auf `mon01`. Die Fassungen im Repo sind Exporte. In Grafana kommen Prometheus und Alertmanager als Datenquellen per Provisioning-Datei, die Loki-Datenquelle ist von Hand angelegt.

Exporte: [`configs/mon01/monitoring/grafana/dashboards/`](../configs/mon01/monitoring/grafana/dashboards/)


## 📣 Benachrichtigungen (ntfy)

Ausgelöste Alerts kommen als Push-Nachricht aufs Handy. Dafür läuft [ntfy](https://ntfy.sh/) als eigener Container im Stack. Der Alertmanager liefert seine Alerts im internen Docker-Netz direkt an ntfy, ohne Umweg über den Reverse Proxy. Das Senden hängt damit nicht an `pve01`. Das Handy holt die Nachrichten über `https://ntfy.home.<domain>` ab, also über `proxy01` mit dessen Let's-Encrypt-Zertifikat. Von unterwegs geht das über das WireGuard-VPN.

ntfy läuft auf `mon01` neben dem Alertmanager und nicht auf `pve01`. Bei einem Ausfall des Hosts wäre ntfy dort mit betroffen und der Alertmanager könnte genau diesen Ausfall nicht mehr melden. Fällt `mon01` selbst aus, schweigen Alertmanager und ntfy gemeinsam, siehe Offene Punkte.

**Zustellung aufs iPhone:** Für die sofortige Zustellung schickt ntfy zu jeder Nachricht einen Weckruf an den öffentlichen Server `ntfy.sh` (`upstream-base-url`), so wie es die [ntfy-Doku](https://docs.ntfy.sh/config/#ios-instant-notifications) für eigene Server vorsieht. Der Weckruf enthält nur die ID der Nachricht und eine Prüfsumme (SHA-256) der Themen-Adresse, keinen Inhalt. Die App holt den Inhalt danach selbst über `proxy01` ab. Ist `proxy01` nicht erreichbar, etwa ohne VPN oder bei einem Ausfall von `pve01`, erscheint nur "New message" ohne Inhalt.

**Themen:** Alle Themen beginnen mit `homelab-`. Die Alerts aus dem Alertmanager laufen in `homelab-alerts`. Sicherungen und Updates haben eigene Themen (`homelab-backups`, `homelab-updates`). Formatiert werden die Alerts mit der eingebauten Vorlage von ntfy für den Alertmanager (`?template=alertmanager`), ein Zusatzdienst ist nicht nötig.

**Anmeldung und Rechte:** Ohne Anmeldung darf niemand lesen oder schreiben (`auth-default-access: deny-all`). Jeder Absender hat einen eigenen Benutzer mit Token und darf nur schreiben. Der Benutzer für das Handy darf nur lesen und hat keine Admin-Rechte. Benutzer und Rechte werden per Kommandozeile auf `mon01` verwaltet. Das Token des Alertmanagers liegt in einer eigenen Datei und nicht in dessen Konfiguration.

**Erreichbarkeit:** Port 2586 ist nur für `proxy01` freigegeben, siehe Hardening. Eine Regel im Gateway braucht es nicht, da `proxy01` und `mon01` im selben VLAN liegen.

Konfiguration: [`configs/mon01/monitoring/ntfy/server.yml`](../configs/mon01/monitoring/ntfy/server.yml), [`configs/mon01/monitoring/alertmanager/alertmanager.yml`](../configs/mon01/monitoring/alertmanager/alertmanager.yml)


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
    - `/opt/monitoring` mit allen Konfigurationen des Stacks, darunter Benutzer, Rechte und Tokens von ntfy
    - eigene Skripte, darunter das Sicherungsskript selbst
    - die SSH-Schlüssel von `root` und Admin-User
    - die Daten von Grafana (Docker-Volume) mit Dashboards, Benutzern und der Loki-Datenquelle
    - eine Liste aller installierten Pakete, `ufw status`, die laufenden Container und die genauen Image-Stände
- **Nicht gesichert:**
    - Grafana-Plugins, nur ihre Liste. Grafana lädt sie selbst nach. Mit Plugins wäre das Archiv rund 168 MB groß, ohne sind es rund 570 KB
    - Messwerte von Prometheus und Logs aus Loki
    - der Nachrichten-Cache von ntfy, er hält Nachrichten ohnehin nur 12 Stunden

Dateien: [`configs/mon01/host-backup/`](../configs/mon01/host-backup/)

Ablauf und Wiederherstellung: [Backup & Wiederherstellung](Backup%20&%20Wiederherstellung.md)


## 📝 Offene Punkte

- Alert, wenn eine Sicherung fehlschlägt oder zu alt ist
- Selbstüberwachung von `mon01` ausbauen (CPU, RAM, Zustand der Container) und eine Meldung von außen, wenn `mon01` ganz ausfällt
- `proxy01` und `cal01` mit Dienst-Prüfung überwachen (Blackbox-Exporter)
- Grafana hinter den Reverse Proxy
- `verify_ssl: false` beim PVE-Exporter ablösen, sobald es eine interne CA gibt
- Loki meldet dauerhaft "Ingester not ready", obwohl Logs ankommen. Ursache klären
- Ziele über DNS-Namen statt Adressen ansprechen (Prometheus, Backup-Skript, Alloy auf `pve01`)
