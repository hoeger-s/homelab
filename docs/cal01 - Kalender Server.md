# cal01 - Kalender Server

Stand: 29.09.2026

Radicale als Server für Kalender, Aufgaben und Kontakte (CalDAV/CardDAV).


## 🖥️ Container

| Option | Value |
|---|---|
| Host | `pve01` |
| Typ | LXC, unprivilegiert, `nesting=1` |
| CTID | 121 |
| Betriebssystem | Debian 13 |
| vCPU | 1 |
| RAM / Swap | 512 MB / 256 MB |
| Disk | 8 GB (`vm-storage`) |
| Autostart | ja (`onboot`, `order=1,up=15`) |


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | eth0 (`vmbr0`) |
| Hostname | cal01 |
| FQDN | cal01.stefan.lab |
| IP CIDR | 10.0.40.14/24 |
| Gateway | 10.0.40.1 |
| DNS | 10.0.40.1 |
| VLAN | Homelab-VLAN (10.0.40.0/24) |


## 🔐 Hardening

- Separaten Admin-User mit `sudo`-Rechten und SSH-Key-Auth angelegt
- Root-SSH-Login und Passwort-Auth deaktiviert (Drop-in unter `/etc/ssh/sshd_config.d/`)
- Proxmox-Gast-Firewall statt `ufw`, Default-Policy `DROP` in beide Richtungen
- Radicale läuft als eigener System-User `radicale`, nicht als root

| Direction | Action | Protocol | Port | Source / Dest | Zweck |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 22 | 10.0.10.0/24 | SSH nur aus Trusted-VLAN |
| in | ACCEPT | tcp | 5232 | 10.0.40.13 | Zugriff über `proxy01` (Caddy) |
| in | ACCEPT | tcp | 5232 | 10.0.10.0/24 | Direktzugriff aus Trusted-VLAN (Fallback) |
| out | ACCEPT | udp/tcp | 53 | any | DNS |
| out | ACCEPT | udp | 123 | any | NTP |
| out | ACCEPT | tcp | 80, 443 | any | Paketquellen |

Regeldatei: [`configs/proxmox/121.fw`](../configs/proxmox/121.fw)


## 📅 Radicale

Installiert aus den Debian-Paketquellen (`radicale` 3.5.3), dazu `python3-bcrypt` für bcrypt-Hashes und `apache2-utils` (nur für `htpasswd`). Radicale spricht selbst nur HTTP auf Port 5232, HTTPS übernimmt `proxy01`.

| Option | Value |
|---|---|
| Adresse | `https://cal.home.<domain>` (über `proxy01`) |
| Backend | `http://10.0.40.14:5232` |
| Auth | `htpasswd`, bcrypt |
| Rechte | `owner_only` (jeder User sieht nur seine eigenen Collections) |
| Storage | `/var/lib/radicale/collections` (Dateien, keine Datenbank) |
| Clients | iOS Kalender/Erinnerungen/Kontakte, Thunderbird (CalDAV/CardDAV) |

```bash
/etc/radicale/
├── config
├── config.orig                         # Debian-Original
└── users                               # htpasswd, Rechte 640 root:radicale, nicht committen
```

Konfiguration: [`configs/radicale/config`](../configs/radicale/config)

> iOS sendet über reines HTTP keine Zugangsdaten (Server-Log zeigt nur anonymous / 401). Deshalb läuft der Zugriff von Anfang an über `proxy01` mit HTTPS.


## 💾 Backup

Container-Backup per `vzdump` auf `pve01`s `hdd-backup`, geplanter Job zusammen mit `proxy01`: wöchentlich `mon 00:05`, letzte 4 Sicherungen behalten, verpasste Läufe werden nachgeholt. Job-Definition: [`configs/proxmox/jobs.cfg`](../configs/proxmox/jobs.cfg)

Die eigentlichen Nutzdaten sind nur der Ordner `/var/lib/radicale/collections` (einzelne `.ics`/`.vcf`-Dateien). Zusätzlich Proxmox-Snapshots an jedem Meilenstein des Aufbaus, die aber auf demselben Storage wie der Container liegen und kein Backup ersetzen.

Die Firewall-Regeln (`/etc/pve/firewall/121.fw`) liegen auf dem Host und sind im Config-Backup von `pve01` enthalten.


## 📝 Offene Punkte

- Direktzugriff aus dem Trusted-VLAN (Port 5232) schließen, sobald der Weg über `proxy01` sich bewährt hat
- Eigener Radicale-User für den KI-Assistenten, Rechte dann per Regeldatei statt `owner_only`
- Monitoring von `cal01` (Node-Exporter)
