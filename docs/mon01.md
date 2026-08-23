# mon01 - Monitoring-Container

Stand: 23-08-2026

LXC-Container für den Monitoring-Stack (Prometheus, Node-Exporter, PVE-Exporter, Grafana, Alertmanager). Stellt Sichtbarkeit auf Host-Ressourcen ('pve01') und Proxmox-VM-/Storage-Ebene her, sowie zentral durchsuchbare Logs beider Hosts.
> Zu diesem Zeitpunkt konfiguriert bevor weitere Komponenten das Host-System zusätzlich belasten um die Ressourcen im Blick zu behalten.

## 🖥️ Aufbau / Konfiguration

| Parameter | Wert |
|---|---|
| Hostname | mon01 |
| FQDN | `mon01.argus.lab` |
| Proxmox CT-ID | 100 |
| Template | Debian 13 (Trixie) |
| CPU | 2 Cores |
| RAM | 2048 / Swap 512 MB |
| Disk | 8 GB, Storage `vm-storage` (SATA-SSD, LVM-Thin) |
| Bridge | `vmbr0` |
| IP CIDR | `192.168.178.20/24` |
| Gateway | `192.168.178.1` |
| Typ | Unprivileged, `nesting=1` |

## 🔐 SSH-Härtung

Analog `pve01`:
- separater Admin-Account mit sudo-Rechten
- Key-only-Auth
- Root-SSH-Login deaktiviert

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

> Port 22 muss in der Container-Firewall separat freigegeben werden (s. Firewall-Abschnitt)

### SSH-Stolpersteine
- `/run/sshd` fehlte initial (tmpfs-Container-Eigenheit) - einmalig behoben mit `mkdir -p /run/sshd && chmod 755 /run/sshd`, seither nicht erneut aufgetreten.
- `systemctl reload ssh` schlägt fehl (`Cannot bind any address`), da der Container Socket-Aktivierung (`ssh.socket`) nutzt. Abweichend zu `pve01`: hier **`systemctl restart ssh`** für SSH-Config-Änderungen verwenden.

## 👀 Monitoring-Stack

| Komponente | Version | Port | Zweck |
|---|---|---|---|
| Prometheus | 3.13.2 | 9090 | Sammelt & speichert alle Metriken |
| Node-Exporter (`mon01`) | 1.12.1 | 9100 | OS-Metriken von `mon01` (CPU, RAM, Disk, Netzwerk) |
| Node-Exporter (`pve01`) | 1.12.1 | 9100 | OS-Metriken von `pve01` (CPU, RAM, Disk, Netzwerk) |
| PVE-Exporter | 3.10.0 (Python, venv) | 9221 | Proxmox-Verwaltungsebene (VMs, Storage-Pools) über die API |
| NVIDIA GPU-Exporter (`pve01`) | 1.13.1 | 9835 | GPU-Metriken (Temperatur, Auslastung, VRAM) von `pve01` |

> Node-Exporter läuft sowohl auf `mon01` als auch auf `pve01`, da PVE-Exporter über die API nur grobe Node-Metriken liefert, nicht die OS-Tiefe (CPU pro Core, Netzwerk-Interface-Details).

### Proxmox API-Zugriff für PVE-Exporter

- Eigener Service-Account mit vordefinierter Rolle für Lesezugriff (keine Schreibrechte), statt bestehenden Admin-Zugang zu nutzen
- Eigener API-Token mit aktivierter Privilege Separation (eigene ACL-Zuweisung, unabhängig von User-Rechten)
- Verbindung ohne SSL-Verifikation (`verify_ssl: false`) wegen selbstsigniertem Zertifikat -> s. offene Punkte

PVE-Exporter fungiert als Proxy: Prometheus scraped `mon01:9221` mit `pve01` als Parameter (`relabel_configs`, `__param_target`).

### Firewall-Anpassung auf `pve01`

Node-Exporter-Port (9100) und GPU-Exporter-Port (9835) auf `pve01` freigegeben, nur für `mon01`:

    IN ACCEPT -source 192.168.178.20 -p tcp -dport 9100 -log nolog
    IN ACCEPT -source 192.168.178.20 -p tcp -dport 9835 -log nolog

> Node-spezifische Regel (`/etc/pve/nodes/pve01/host.fw`)

### PVE-Exporter-Stolpersteine

- PVE-Exporter-Scraping in `prometheus.yml` benötigt `relabel_configs` (Proxy-Prinzip: ein Port, mehrere Ziele über `target`-Parameter) - reine `static_configs` reichen nicht.

## 📜 Logging (Loki + Alloy)

| Komponente | Version | Port | Läuft auf | Zweck |
|---|---|---|---|---|
| Loki | 3.7.6 | 3100 | `mon01` | Zentraler Log-Speicher, LogQL-Abfragen |
| Alloy (`mon01`) | 1.18.1 | - | `mon01` | Liest lokales systemd-Journal, pusht an `localhost:3100` |
| Alloy (`pve01`) | 1.18.1 | - | `pve01` | Liest lokales systemd-Journal, pusht an `mon01:3100` |

> Storage-Typ: Filesystem (`/var/lib/loki`), Retention 168h (7 Tage), durchgesetzt über den Loki-Compactor. Kein Auth (`auth_enabled: false`). Absicherung ausschließlich über Firewall (LAN-intern, siehe unten).

> Alloy pusht die Logs aktiv (umgekehrte Richtung zu Prometheus, das die Exporter aktiv abfragt), deshalb läuft auf beiden Hosts eine eigene Alloy-Instanz, jede liest nur ihr eigenes lokales Journal.

Label-Set pro Log-Zeile: `host` (mon01/pve01), `job` (systemd-journal), `unit` (systemd-Service-Name, per Relabeling aus dem Journal-Metadatenfeld extrahiert), `service_name`, `detected_level`.

## 📈 Grafana

Grafana 13.1.1, Port 3000. Prometheus als Datenquelle über `http://localhost:9090`, Loki über `http://localhost:3100`

Referenz-Dashboard "Node Exporter Full" (ID 1860) importiert.
> Zusätzlich eigenes Dashboard "Homelab Overview" konfiguriert für einen schnellen Überblick über die wichtigsten Ressourcen und VMs/Container. Log-Abfrage aktuell nur über Grafana "Explore".

### Alert-Regeln

Fünf Grafana-managed Regeln, Ordner "ARGUS", Gruppe `argus-infra`, Notification nur über Grafana-UI (kein Contact Point).

| Regel | Bedingung | Pending Period |
|---|---|---|
| `node_exporter_pve01 down`| `up{job="node_exporter_pve01"}` < 1 | 2m |
| `pve01 CPU-Auslastung hoch` | CPU-Last > 85% | 5m |
| `pve01 RAM-Auslastung hoch` | RAM-Belegung > 85% | 5m |
| `Storage-Pool fast voll` | Belegung > 85% | 10m |
| `pve01 GPU-Auslastung hoch` | GPU-Last > 85% | 5m |

> `node_exporter_pve01 down` erkennt Exporter-Ausfall, nicht Host-Totalausfall: `mon01` läuft als Container auf `pve01` - fällt der Host komplett aus, ist auch das Monitoring down. Externes Monitoring geplant s. offene Punkte.

## 🔥 Firewall

Ports 22 (SSH), 9090 (Prometheus) und 3000 (Grafana) auf LAN-Subnetz beschränkt:

| Type | Action | Protocol | Source | D.Port | Log Level |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 192.168.178.0/24 | 22 | nolog |
| in | ACCEPT | tcp | 192.168.178.0/24 | 3000 | nolog |
| in | ACCEPT | tcp | 192.168.178.0/24 | 9090 | nolog |
| in | ACCEPT | tcp | 192.168.178.10 | 3100 | nolog |

> Keine Client-IP-Einschränkung bei 22/3000/9090, da IPs per DHCP bezogen werden. Granularere Segmentierung vorgesehen für die geplante VLAN-Einführung. Port 3100 (Loki) ist Ausnahme: eng auf `pve01` als einzige erwartete Quelle beschränkt statt aufs ganze Subnetz, da nur Alloy von dort pusht.

## 📝 Offene Punkte

- `verify_ssl: false` bei PVE-Exporter - eigene CA als saubere Lösung
- Prometheus-Retention/Storage-Sizing noch nicht bewusst konfiguriert (Default (15 tage) aktiv)
- Externes/unabhängiges Monitoring für `pve01`-Totalausfall
- Logging bisher nur systemd-Journal. Keine Anwendungslogs, keine Proxmox-Task-Logs (/var/log/pve/tasks/)
- Kein Log-Dashboard/keine Log-Alert-Regeln in Grafana, nur manuelle Abfrage über Explore
- Retention-Löschung durch den Loki-Compactor (7 Tage) noch nicht über vollen Zyklus verifiziert
- Alloy-Debug-UI (Port 12345) nicht firewalled, aktuell ungenutzt
