# proxy01 - Reverse Proxy

Stand: 26.10.2026

Zentraler Reverse Proxy des Homelabs. Caddy nimmt alle Anfragen an `*.home.<domain>` entgegen und leitet sie an den jeweiligen Dienst weiter. Endgeräte bauen eine verschlüsselte Verbindung über TLS (Transport Layer Security) nur bis zu `proxy01` auf. Caddy weist sich dabei mit einem Wildcard-Zertifikat von Let's Encrypt aus, dem alle Geräte von sich aus vertrauen. Kein Dienst ist aus dem Internet erreichbar, Zugriff von unterwegs nur über das WireGuard-VPN.


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

> `proxy01` startet nach `pve01` als erster Container, die übrigen folgen erst 15 Sekunden später, da die Dienste von unterwegs aus nur über den Proxy erreichbar sind.


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | `eth0` -> Bridge `vmbr0`, `tag=40` |
| Hostname | proxy01 |
| FQDN | proxy01.internal |
| IP CIDR | 10.0.40.10/24 |
| Gateway | 10.0.40.1 |
| DNS | 10.0.40.1, Suchdomäne `internal` |
| VLAN | Homelab (VLAN 40) |

Die IP-Adresse ist in der Container-Konfiguration auf `pve01` fest eingetragen und wird nicht per DHCP vom UniFi-Gateway vergeben. Unter `proxy01.internal` ist der Container per DNS-Eintrag im Gateway erreichbar.

DNS-Server und Suchdomäne stehen ebenfalls fest in der Container-Konfiguration. Ohne eigene Angabe übernimmt Proxmox beim Anlegen die Werte des Hosts und der Container würde das Gateway im Management-VLAN fragen.


## 🔐 Hardening

- Separater Admin-User mit `sudo` und SSH-Key
- Root- und Passwort-Login per SSH deaktiviert
- Proxmox-Firewall statt `ufw`, Default-Policy `DROP` in beide Richtungen

Die Proxmox-Firewall filtert auf `pve01`, bevor ein Paket den Container erreicht oder verlässt. Wer im Container `root` ist, kann die Regeln deshalb weder sehen noch lockern. Mit `ufw` lägen sie im Container selbst. Auch ausgehend ist nur erlaubt, was der Proxy für seine Aufgaben braucht: DNS, Zeit, Web für Updates, Zertifikate und Weiterleitungen sowie Radicale auf `cal01`. Ein übernommener Proxy kann sich so kaum weiter im Homelab ausbreiten.

**Regeln (`120.fw`):**

| Direction | Action | Protocol | Port | Source / Dest | Zweck |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 22 | `admin` | SSH nur von der Workstation |
| in | ACCEPT | tcp | 80 | `trusted` | Umleitung auf HTTPS |
| in | ACCEPT | tcp | 443 | `trusted` | HTTPS aus Trusted |
| in | ACCEPT | tcp | 443 | `vpn` | HTTPS aus dem WireGuard-VPN |
| in | ACCEPT | tcp | 443 | `ki01` | KI-Assistent (Zugriff auf den Kalender) |
| out | ACCEPT | udp/tcp | 53 | any | DNS |
| out | ACCEPT | udp | 123 | any | Zeit (NTP) |
| out | ACCEPT | tcp | 80, 443 | any | Updates, Let's Encrypt, deSEC-API, Weiterleitung an `ki01` |
| out | ACCEPT | tcp | 5232 | `cal01` | Radicale (Weiterleitung) |

Quellen und Ziele sind Aliase aus `cluster.fw` (siehe [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md#-firewall-in-proxmox)).

Regeldatei: [`configs/pve01/firewall/120.fw`](../configs/pve01/firewall/120.fw)

Im Gateway kommen dazu die Regeln "Trusted zu proxy01" (80, 443) und "VPN zu proxy01" (443), siehe [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md#-firewall-im-gateway-zonen). Die VPN-Zone darf ins Homelab nur hierher, alle anderen Wege aus dem VPN sind gesperrt. Von unterwegs gibt es damit genau eine Tür. Dahinter verlangt jeder Dienst eine Anmeldung. Da die Anmeldung auf den eigenen Geräten aber meist gespeichert ist, sollte bei Verlust eines Geräts dessen VPN-Profil im Gateway gesperrt werden.

> Die Regeln liegen auf `pve01` unter `/etc/pve/firewall/120.fw`.


## 🔒 Zertifikate & DNS

**Ziel:** echte Zertifikate, denen alle Geräte vertrauen (auch iOS), ohne eigene CA (Certificate Authority) und ohne dass etwas aus dem Internet erreichbar sein muss.

Beteiligt sind dabei drei Stellen: [Let's Encrypt](https://letsencrypt.org) ist die CA und stellt das Zertifikat kostenlos aus. [deSEC](https://desec.io) führt das öffentliche DNS für `home.<domain>`. Bei Strato ist die Domain registriert, dort liegt auch das DNS der Hauptdomain. Caddy beantragt und erneuert das Zertifikat selbstständig.

- **DNS-01-Challenge statt HTTP-Challenge:** Vor dem Ausstellen prüft Let's Encrypt, ob die Domain wirklich dem Antragsteller gehört. Bei der HTTP-Challenge ruft Let's Encrypt dafür über Port 80 einen Prüfcode vom Server ab, der Proxy müsste also aus dem Internet erreichbar sein. Bei der DNS-01-Challenge legt Caddy den Prüfcode als TXT-Eintrag bei deSEC ab und Let's Encrypt liest ihn dort aus. Ins Homelab muss dabei niemand. Wildcard-Zertifikate stellt Let's Encrypt ohnehin nur auf diesem Weg aus.
- **Subdomain-Delegation:** Nur `home.<domain>` ist per NS-Eintrag an deSEC delegiert, die Hauptdomain bleibt bei Strato. Caddy muss den Prüfcode automatisch eintragen können. deSEC bietet dafür eine API, Strato nicht. Ein Umzug des gesamten DNS hätte auch die Einträge für die Mail betroffen. So bleibt die Hauptdomain unangetastet.
- **Wildcard-Zertifikat** `*.home.<domain>`: Alle verschlüsselten Verbindungen enden an `proxy01`. Auch Zertifikate pro Dienst lägen deshalb alle dort und brächten in diesem Aufbau keine zusätzliche Sicherheit, nur mehr Aufwand. Jeder neue Dienst bräuchte ein eigenes Zertifikat und der Token müsste für jeden Namen schreiben dürfen. Das Wildcard-Zertifikat deckt dagegen alle Dienste ab. Nebenbei tauchen so keine Dienstnamen in den öffentlichen Logs auf, in denen jedes Let's-Encrypt-Zertifikat landet (Certificate Transparency). Erbeutet jemand den privaten Schlüssel des Zertifikats von `proxy01`, kann er sich allerdings für jeden Namen unter `home.<domain>` ausgeben. Zertifikate pro Dienst kommen mit der internen CA für die Strecke Proxy -> Dienst.
- **Interne Namensauflösung:** Das Gateway beantwortet alle Namen unter `*.home.<domain>` mit `10.0.40.10`. Öffentlich existieren für die Dienstnamen keine Einträge, von außen lässt sich keiner auflösen. Geräte im Heimnetz und im VPN fragen das Gateway.
- **Eingeschränkter API-Token:** Der deSEC-Token darf per Token-Policy nur den TXT-Eintrag `_acme-challenge.home.<domain>` für den Prüfcode schreiben. Wird er geklaut, kann damit niemand Namen unter `home.<domain>` auf einen fremden Server umleiten oder Zertifikate für beliebige Namen holen. Möglich bleibt nur ein weiteres Wildcard-Zertifikat. Der Token liegt aber nur auf `proxy01`, wo Zertifikat und privater Schlüssel ohnehin schon liegen.


## ⚙️ Caddy

Caddy statt Nginx Proxy Manager, weil die Konfiguration hier eine einzige Datei ist. Beim Nginx Proxy Manager liegt sie in einer Datenbank und seine Weboberfläche verwaltet Zertifikat und Token selbst. Diese Oberfläche wäre zwar bequemer, müsste aber zusätzlich abgesichert werden.

Installiert wurde Caddy aus dem offiziellen Caddy-APT-Repo, danach wurde es durch einen eigenen Build mit dem Modul [`caddy-dns/desec`](https://github.com/caddy-dns/desec) ersetzt. `dpkg-divert` und `update-alternatives` verhindern, dass `apt upgrade` das Binary still durch die Standard-Variante ohne DNS-Modul ersetzt. Die Zertifikatserneuerung würde sonst lautlos scheitern. Updates des eigenen Builds laufen über `caddy upgrade`.

```bash
/etc/caddy/
├── Caddyfile
└── desec.env                           # API-Token, Rechte 600, nicht im Repo

/etc/systemd/system/caddy.service.d/
└── desec.conf                          # EnvironmentFile=/etc/caddy/desec.env
```

Konfiguration: [`configs/proxy01/caddy/Caddyfile`](../configs/proxy01/caddy/Caddyfile)

**Angebundene Dienste:**

| Name | Ziel | Dienst |
|---|---|---|
| `cal.home.<domain>` | `10.0.40.30:5232` (HTTP) | Radicale auf [cal01](cal01%20-%20Kalender%20Server.md) |

Dazu die Weboberfläche des KI-Assistenten (eigenes Projekt, nicht in diesem Repo). Unbekannte Namen weist Caddy per `abort` sofort ab.

> Der Weg vom Proxy zum Dienst ist unverschlüsseltes HTTP innerhalb des Homelabs. Verschlüsselt wird er erst mit einer internen CA, siehe Offene Punkte.


## 📊 Monitoring

`proxy01` wird noch nicht überwacht. Geplant ist eine Dienst-Prüfung von `mon01` aus, siehe Offene Punkte.


## 📜 Logging

Die Logs von `proxy01` gehen noch nicht an Loki auf `mon01`. Geplant ist Alloy wie auf `pve01`, siehe Offene Punkte.


## 💾 Backup

Komplett über den Container-Job auf `pve01` (siehe [pve01 - Proxmox Host](pve01%20-%20Proxmox%20Host.md#-backup)). Die Sicherung enthält auch Zertifikat und deSEC-Token.

Ablauf und Wiederherstellung: [Backup & Wiederherstellung](Backup%20&%20Wiederherstellung.md)


## 📝 Offene Punkte

- Weitere Dienste anbinden (als nächstes Grafana)
- Authelia vor die Dienste setzen (Anmeldung mit MFA)
- Strecke Proxy -> Dienst mit einer internen CA verschlüsseln
- Dienst-Prüfung von `proxy01` mit Alert bei Ausfall und bei bald ablaufendem Zertifikat (Blackbox-Exporter, siehe [mon01 - Monitoring Host](mon01%20-%20Monitoring%20Host.md))
- Logs per Alloy an Loki auf `mon01` schicken
- Ausstehende Updates einspielen
