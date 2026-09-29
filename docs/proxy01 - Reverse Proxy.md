# proxy01 - Reverse Proxy

Stand: 29.09.2026

Zentraler Reverse-Proxy des Homelabs. Caddy nimmt alle Anfragen an `*.home.<domain>` entgegen, terminiert TLS mit einem öffentlich vertrauenswürdigen Let's-Encrypt-Wildcard-Zertifikat und reicht sie an die jeweiligen Dienste weiter. Kein Dienst ist aus dem Internet erreichbar, Zugriff von unterwegs nur über WireGuard-VPN.


## 🖥️ Container

| Option | Value |
|---|---|
| Host | `pve01` |
| Typ | LXC, unprivilegiert, `nesting=1` |
| CTID | 120 |
| Betriebssystem | Debian 13 |
| vCPU | 1 |
| RAM / Swap | 512 MB / 256 MB |
| Disk | 4 GB (`vm-storage`) |
| Autostart | ja (`onboot`, `order=1,up=15`) |


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | eth0 (`vmbr0`) |
| Hostname | proxy01 |
| FQDN | proxy01.stefan.lab |
| IP CIDR | 10.0.40.13/24 |
| Gateway | 10.0.40.1 |
| DNS | 10.0.40.1 |
| VLAN | Homelab-VLAN (10.0.40.0/24) |


## 🔐 Hardening

- Separaten Admin-User mit `sudo`-Rechten und SSH-Key-Auth angelegt
- Root-SSH-Login und Passwort-Auth deaktiviert (Drop-in unter `/etc/ssh/sshd_config.d/`)
- Proxmox-Gast-Firewall statt `ufw`, Default-Policy `DROP` in beide Richtungen

| Direction | Action | Protocol | Port | Source / Dest | Zweck |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 22 | 10.0.10.0/24 | SSH nur aus Trusted-VLAN |
| in | ACCEPT | tcp | 443 | 10.0.10.0/24 | HTTPS aus Trusted-VLAN |
| in | ACCEPT | tcp | 80 | 10.0.10.0/24 | Redirect auf HTTPS |
| in | ACCEPT | tcp | 443 | 192.168.2.0/24 | HTTPS aus dem WireGuard-VPN |
| out | ACCEPT | udp/tcp | 53 | any | DNS |
| out | ACCEPT | udp | 123 | any | NTP |
| out | ACCEPT | tcp | 80, 443 | any | Paketquellen, Let's Encrypt, deSEC-API, Backends |
| out | ACCEPT | tcp | 5232 | 10.0.40.14 | Radicale-Backend (cal01) |

Regeldatei: [`configs/proxmox/120.fw`](../configs/proxmox/120.fw)

Zusätzlich auf dem UniFi-Gateway: VPN-Zone -> nur `10.0.40.13:443/tcp` erlaubt. Von unterwegs gibt es damit genau einen Weg ins Homelab.


## 🔒 Zertifikate & DNS

**Ziel:** Echte, von allen Geräten (inkl. iOS) vertraute Zertifikate für interne Dienste, ohne eigene CA und ohne öffentliche Erreichbarkeit.

- **DNS-01-Challenge** statt HTTP-Challenge: Let's Encrypt prüft einen TXT-Eintrag im DNS, der Proxy muss dafür nicht aus dem Internet erreichbar sein.
- **Subdomain-Delegation:** Die Hauptdomain bleibt beim Registrar (Strato, dort läuft auch Mail). Nur `home.<domain>` ist per NS-Eintrag an [deSEC](https://desec.io) delegiert. Grund: Strato bietet keine DNS-API, ein Umzug der ganzen Domain hätte die Mail-Funktionen gekostet.
- **Wildcard-Zertifikat** `*.home.<domain>`: Alle Let's-Encrypt-Zertifikate werden öffentlich protokolliert (Certificate Transparency). Mit Einzelzertifikaten wäre jeder Dienstname öffentlich einsehbar, so nur der Wildcard.
- **Interne Namensauflösung:** Ein Wildcard-DNS-Eintrag auf dem UniFi-Gateway (`*.home.<domain>` -> `10.0.40.13`). Öffentlich existieren für die Dienstnamen keine DNS-Einträge.
- **Eingeschränkter API-Token:** Der deSEC-Token darf per Token-Policy ausschließlich den TXT-Eintrag `_acme-challenge.home.<domain>` schreiben.


## ⚙️ Caddy

Installiert aus dem offiziellen Caddy-APT-Repo, danach durch einen Custom-Build mit dem Modul [`caddy-dns/desec`](https://github.com/caddy-dns/desec) ersetzt. `dpkg-divert` und `update-alternatives` verhindern, dass `apt upgrade` das Binary still durch die Standard-Variante ohne DNS-Modul ersetzt (Zertifikatserneuerung würde sonst lautlos scheitern). Updates des Custom-Builds über `caddy upgrade`.

```bash
/etc/caddy/
├── Caddyfile
└── desec.env                           # API-Token, Rechte 600, nicht committen

/etc/systemd/system/caddy.service.d/
└── desec.conf                          # EnvironmentFile=/etc/caddy/desec.env
```

Konfiguration: [`configs/caddy/Caddyfile`](../configs/caddy/Caddyfile)

**Angebundene Dienste:**

| Name | Ziel | Dienst |
|---|---|---|
| `cal.home.<domain>` | `10.0.40.14:5232` (HTTP) | Radicale auf [cal01](cal01%20-%20Kalender%20Server.md) |

Unbekannte Namen werden per `abort` sofort abgewiesen.


## 💾 Backup

Container-Backup per `vzdump` auf `pve01`s `hdd-backup`. Das sichert den kompletten Container inkl. Konfiguration und Zertifikaten, Restore mit einem einzigen `pct restore`. Geplanter Job (zusammen mit `cal01`): wöchentlich `mon 00:05` (Backup-Fenster in der Nacht So->Mo, siehe Zeitschaltung `pve01`), letzte 4 Sicherungen behalten, verpasste Läufe werden beim nächsten Start nachgeholt. Job-Definition: [`configs/proxmox/jobs.cfg`](../configs/proxmox/jobs.cfg)
Zusätzlich Proxmox-Snapshots an jedem Meilenstein des Aufbaus, die aber auf demselben Storage wie der Container liegen und kein Backup ersetzen.

Die Firewall-Regeln (`/etc/pve/firewall/120.fw`) liegen auf dem Host und sind im Config-Backup von `pve01` enthalten.


## 📝 Offene Punkte

- Weitere Dienste anbinden (Grafana)
- Monitoring von `proxy01` (Node-Exporter, Zertifikats-Ablauf als Alert)
