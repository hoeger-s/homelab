# cal01 - Kalender Server

Stand: 26.10.2026

Radicale als Server für Kalender, Aufgaben und Kontakte (CalDAV/CardDAV). iOS-Geräte und Thunderbird greifen über den Reverse Proxy darauf zu.


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
| Autostart | ja (`onboot`, `order=2`) |

> `cal01` startet als zweiter Container direkt nach `proxy01` und noch vor dem KI-Assistenten, der auf Kalender und Aufgaben zugreift.


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | `eth0` -> Bridge `vmbr0`, `tag=40` |
| Hostname | cal01 |
| FQDN | cal01.internal |
| IP CIDR | 10.0.40.30/24 |
| Gateway | 10.0.40.1 |
| DNS | 10.0.40.1, Suchdomäne `internal` |
| VLAN | Homelab (VLAN 40) |

Die IP-Adresse ist in der Container-Konfiguration auf `pve01` fest eingetragen und wird nicht per DHCP vom UniFi-Gateway vergeben. Unter `cal01.internal` ist der Container per DNS-Eintrag im Gateway erreichbar. `.30` ist die erste Adresse im Block Anwendungen.

DNS-Server und Suchdomäne stehen ebenfalls fest in der Container-Konfiguration. Ohne eigene Angabe übernimmt Proxmox beim Anlegen die Werte des Hosts und der Container würde das Gateway im Management-VLAN fragen.


## 🔐 Hardening

- Separater Admin-User mit `sudo` und SSH-Key
- Root- und Passwort-Login per SSH deaktiviert
- Proxmox-Firewall statt `ufw`, Default-Policy `DROP` in beide Richtungen
- Radicale läuft als eigener System-User `radicale`, nicht als root

Die Proxmox-Firewall filtert auf `pve01`, bevor ein Paket den Container erreicht oder verlässt. Wer im Container `root` ist, kann die Regeln deshalb weder sehen noch lockern. Mit `ufw` lägen sie im Container selbst. Auch ausgehend ist nur erlaubt, was der Container für Updates braucht: DNS, Zeit und Web. Radicale selbst baut keine Verbindungen nach außen auf. Ein übernommener Kalender-Server kann sich so kaum weiter im Homelab ausbreiten.

**Regeln (`121.fw`):**

| Direction | Action | Protocol | Port | Source / Dest | Zweck |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 22 | `admin` | SSH nur von der Workstation |
| in | ACCEPT | tcp | 5232 | `proxy01` | Zugriff über den Reverse Proxy |
| in | ACCEPT | tcp | 5232 | `trusted` | Rückfallweg direkt aus Trusted |
| out | ACCEPT | udp/tcp | 53 | any | DNS |
| out | ACCEPT | udp | 123 | any | Zeit (NTP) |
| out | ACCEPT | tcp | 80, 443 | any | Updates |

Quellen sind Aliase aus `cluster.fw` (siehe [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md#-firewall-in-proxmox)).

Regeldatei: [`configs/pve01/firewall/121.fw`](../configs/pve01/firewall/121.fw)

Im Gateway kommt dazu die Regel "Trusted zu cal01" (5232) für den Rückfallweg, siehe [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md#-firewall-im-gateway-zonen). Der normale Weg geht über `proxy01`. Über den Rückfallweg am Proxy vorbei bleiben Kalender, Aufgaben und Kontakte aus dem Heimnetz auch bei einem Ausfall von `proxy01` erreichbar.

> Die Regeln liegen auf `pve01` unter `/etc/pve/firewall/121.fw`.


## 📅 Radicale

Installiert aus den Debian-Paketquellen (`radicale` 3.5.3), dazu `python3-bcrypt` für bcrypt-Hashes und `apache2-utils` (nur für `htpasswd`). Radicale spricht selbst nur HTTP auf Port 5232, HTTPS übernimmt `proxy01`.

| Option | Value |
|---|---|
| Adresse | `https://cal.home.<domain>` (über `proxy01`) |
| Rückfallweg | `http://10.0.40.30:5232` (nur aus Trusted) |
| Anmeldung | `htpasswd`, bcrypt |
| Rechte | Regeldatei `/etc/radicale/rights`: jeder sieht seine eigenen Sammlungen, dazu gezielte Freigaben einzelner Kalender für weitere Benutzer |
| Verlauf | jede Änderung als Git-Commit im Datenordner |
| Storage | `/var/lib/radicale/collections` (Dateien, keine Datenbank) |
| Clients | iOS Kalender, Erinnerungen, Kontakte, Thunderbird |

```bash
/etc/radicale/
├── config
├── config.orig                         # Debian-Original
├── rights                              # Freigaben, nicht im Repo
├── rights.orig                         # Debian-Original
└── users                               # htpasswd, Rechte 640 root:radicale, nicht im Repo
```

Konfiguration: [`configs/cal01/radicale/config`](../configs/cal01/radicale/config)

**Freigaben:** Ein eigener Benutzer für den KI-Assistenten darf genau zwei Sammlungen lesen und schreiben (Aufgaben und einen Kalender), sonst nichts. Kontakte sind für ihn gesperrt. Die Regeldatei statt der eingebauten Einstellung `owner_only` braucht es, sobald ein zweiter Benutzer auf einzelne fremde Kalender zugreifen soll. So bekommt der KI-Assistent genau die zwei Sammlungen und nicht mehr.

**Verlauf per Git:** Radicale führt nach jeder Änderung einen Befehl aus (`hook`). Hier ist das ein `git commit` im Datenordner, mit dem Benutzer in der Nachricht. Hat ein Client etwas kaputt synchronisiert, lässt sich der alte Stand einfach aus dem Verlauf zurückholen.

> iOS sendet über reines HTTP keine Zugangsdaten, im Server-Log steht dann nur anonymous / 401. Deshalb läuft der Zugriff über `proxy01` mit HTTPS.


## 📊 Monitoring

`cal01` wird noch nicht überwacht. Geplant ist eine Dienst-Prüfung von `mon01` aus, siehe Offene Punkte.


## 📜 Logging

Die Logs von `cal01` gehen noch nicht an Loki auf `mon01`. Geplant ist Alloy wie auf `pve01`, siehe Offene Punkte.


## 💾 Backup

Komplett über den Container-Job auf `pve01` (siehe [pve01 - Proxmox Host](pve01%20-%20Proxmox%20Host.md#-backup)). Die Sicherung enthält auch die Firewall-Regeln des Containers. Die eigentlichen Nutzdaten sind nur der Ordner `/var/lib/radicale/collections` mit einzelnen `.ics`- und `.vcf`-Dateien, dazu der Git-Verlauf im selben Ordner.

Ablauf und Wiederherstellung: [Backup & Wiederherstellung](Backup%20&%20Wiederherstellung.md)


## 📝 Offene Punkte

- Rückfallweg (Port 5232 aus Trusted) schließen
- Strecke Proxy -> Radicale mit einer internen CA (Certificate Authority) verschlüsseln
- Dienst-Prüfung von `cal01` mit Alert bei Ausfall (Blackbox-Exporter, siehe [mon01 - Monitoring Host](mon01%20-%20Monitoring%20Host.md))
- Logs per Alloy an Loki auf `mon01` schicken
