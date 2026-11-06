# Netzwerk & Sicherheit

Stand: 06.11.2026

Wie das Heimnetz aufgeteilt ist, wer wohin darf und warum.


## 🧭 Aufbau

```
Internet
   │
FritzBox (nur Übergabe, Exposed Host auf das Gateway)
   │
UniFi Cloud Gateway Ultra (WAN an Port 5)
   ├── Port 1  Workstation           (Trusted)
   ├── Port 2  pve01                 (Trunk: nativ Management, getaggt Homelab)
   ├── Port 3  mon01                 (Homelab)
   └── Port 4  U7 Lite Access Point  (Trunk: nativ Default, getaggt Trusted, IoT, Gäste, Management)
```

Die FritzBox ist nur für die Verbindung zum Kabelanbieter zuständig. WLAN, Portfreigaben und Fernzugriff sind dort aus und alles läuft über das UniFi-Gateway. Einen eigenen Switch gibt es noch nicht. Die Geräte hängen direkt am Gateway.

| Port | Profil | Natives VLAN | Getaggt | Gerät |
|---|---|---|---|---|
| 1 | Trusted-Access | Trusted | keine | Workstation `10.0.10.50` |
| 2 | pve01-Trunk | Management | Homelab | `pve01` `10.0.99.10` |
| 3 | Homelab-Access | Homelab | keine | `mon01` `10.0.40.90` |
| 4 | AP-Trunk | Default | Trusted, IoT, Gäste, Management | U7 Lite `10.0.99.3` |


## 🌐 VLANs

| Netz | VLAN | Subnetz | Zone | DHCP | Zweck |
|---|---|---|---|---|---|
| Default | 1 | `10.0.0.0/24` | Intern | aus | geparkt, lässt sich in UniFi nicht löschen |
| Trusted | 10 | `10.0.10.0/24` | Intern | `.100-.199` | eigene Geräte |
| IoT | 20 | `10.0.20.0/24` | Untrusted | `.100-.199` | Smart-Home, nur Internet |
| Gäste | 30 | `10.0.30.0/24` | Hotspot | `.100-.250` | Gäste-WLAN mit Client-Isolation |
| Homelab | 40 | `10.0.40.0/24` | Homelab | `.200-.254` | Server und Dienste |
| Management | 99 | `10.0.99.0/24` | Management | aus | Proxmox-Host, Netzwerkgeräte |
| VPN | - | `192.168.2.0/24` | VPN | fest je Profil | WireGuard-Clients |


## 🔢 IP-Schema

**Grundregel:** `10.0.<VLAN>.0/24`. Die Zahl im dritten Oktett ist die VLAN-Nummer. Jede Adresse lässt sich so ohne nachzuschlagen einordnen.

**Raster:** Es legt fest, in welchem Bereich etwas liegt, wenn ein Netz es braucht. Bereiche, die ein Netz nicht braucht, bleiben frei. IoT hat z. B. nur Gateway und den DHCP-Pool.

| Bereich | Verwendung |
|---|---|
| `.1` | Gateway |
| `.2-.9` | Netzwerkgeräte |
| `.10-.49` | feste Server und Dienste |
| `.50-.99` | DHCP-Reservierungen |
| `.100-.199` | DHCP-Pool |
| `.200-.254` | Reserve |

**Ausnahme Gäste (VLAN 30):** Gäste brauchen keine festen Adressen, also auch keine Reservierungen. Der DHCP-Bereich reicht deshalb bis `.250`.

**Ausnahme Homelab (VLAN 40):** Dort gibt es keine Endgeräte, also auch keine Reservierungen. Stattdessen sind `.10-.199` in Blöcke zu je 20 Adressen aufgeteilt. Ein Block pro Rolle. DHCP gibt es nur in `.200-.254`, für die Ersteinrichtung neuer Container oder VMs.

| Block | Rolle | Belegt |
|---|---|---|
| `.10-.29` | Core | `.10` proxy01 |
| `.30-.49` | Anwendungen | `.30` cal01 |
| `.50-.69` | KI | `.50` ki01 (KI-Assistent) |
| `.70-.89` | Storage | frei (NAS geplant) |
| `.90-.109` | Monitoring / Logging | `.90` mon01 |
| `.110-.199` | frei | |

"Core" heißt: Fällt der Dienst aus, funktionieren andere nicht mehr. Fällt der Proxy aus, ist alles dahinter weg, also ist er ein Core-Dienst. Fällt der Kalender auf `cal01` aus, fehlt nur der Kalender, alles andere läuft weiter. Er ist also eine Anwendung.

**Management (VLAN 99):** `.3` Access Point, `.10` pve01. Später kommen noch ein Switch (`.2`) und perspektivisch Mini-PCs als weitere Proxmox-Hosts hinzu. `mon01` steht bewusst nicht hier. Ins Management-Netz kommen nur Geräte, die andere verwalten oder tragen. `mon01` ist ein normaler Server, der Dienste anbietet.

Alle Server haben ihre Adresse fest auf dem Gerät eingestellt, nicht per DHCP. Proxy, Proxmox und Monitoring sollen nicht davon abhängen, dass DHCP läuft.


## 🏷️ Namen

DNS macht das Gateway. Interne Rechnernamen laufen unter `.internal`, als feste Host-Einträge im Gateway:

| Name | Adresse |
|---|---|
| `pve01.internal` | `10.0.99.10` |
| `proxy01.internal` | `10.0.40.10` |
| `cal01.internal` | `10.0.40.30` |
| `ki01.internal` | `10.0.40.50` |
| `mon01.internal` | `10.0.40.90` |

Dazu ein Wildcard-Eintrag `*.home.<domain>` -> `10.0.40.10`. Damit landen alle Dienstnamen beim Reverse Proxy. Öffentlich gibt es für die Dienstnamen keine DNS-Einträge.

Es gibt also drei Namensräume:

| Namensraum | Beispiel | Wofür |
|---|---|---|
| eigene Domain | `cal.home.<domain>` | Dienste hinter dem Proxy, nur damit gibt es echte Zertifikate |
| `.internal` | `pve01.internal` | Rechnernamen im Heimnetz |
| Adressen | `10.0.99.10` | Wege zwischen den Servern (z. B. Prometheus -> pve01) |


## 🧱 Firewall im Gateway (Zonen)

Die Firewall im Gateway arbeitet mit Zonen, also Gruppen von Netzen, denen gleich viel vertraut wird. Jedes Netz gehört zu genau einer davon. Regeln gelten von Zone zu Zone und lassen sich auf einzelne Netze oder Adressen eingrenzen. Die eigenen Geräte (Trusted) liegen in "Intern", zusammen mit dem geparkten Default-Netz. Homelab und Management haben je eine eigene Zone, IoT ist allein in "Untrusted". Server und Smart-Home-Geräte haben nichts gemeinsam. Die Zone jedes Netzes steht in der Tabelle unter VLANs. Gesperrt ist alles, was nicht ausdrücklich erlaubt ist.

Adressen stehen in den Regeln nie direkt, sondern über Netzwerklisten (`proxy01`, `cal01`, `ki01`, `mon01`, `pve01`, `admin-geraete`). Ändert sich eine Adresse, ändert sich nur die Liste. Die Regeln sind hier nach ihrem Namen aufgeführt, die Regel-ID ist in UniFi nicht eindeutig.

**Erlaubte Wege**

| Regel | Von | Nach | Port | Zweck |
|---|---|---|---|---|
| Trusted zu proxy01 | Trusted | `proxy01` | 80, 443 | alle Dienste über `*.home.<domain>` (80 nur Umleitung) |
| Trusted zu mon01 | Trusted | `mon01` | 3000 | Grafana |
| Trusted zu cal01 | Trusted | `cal01` | 5232 | Rückfallweg am Proxy vorbei |
| Trusted zu ki01 | Trusted | `ki01` | 443 | Weboberfläche des KI-Assistenten direkt |
| Admin zu Homelab | `admin-geraete` | Homelab | 22 | SSH auf Server und Container |
| Admin zu pve01 | `admin-geraete` | `pve01` | 22, 8006 | SSH und Weboberfläche Proxmox |
| VPN zu proxy01 | WireGuard | `proxy01` | 443 | unterwegs nur der Proxy |
| mon01 zu pve01 | `mon01` | `pve01` | 22, 8006, 9100, 9835 | Exporter, Proxmox-API, Host-Sicherung |
| pve01 zu mon01 | `pve01` | `mon01` | 3100 | Logs an Loki |

Server und Container werden nur von der Workstation aus verwaltet (Least-Privilege-Prinzip). Andere Endgeräte verwalten im Homelab nichts. Die Workstation hat ihre Adresse fest per DHCP-Reservierung und hängt per Ethernet am Gateway. Über WLAN bekäme sie eine andere Adresse und hätte keinen Admin-Zugriff mehr. Eine Regel nach Adresse prüft nur, woher eine Verbindung kommt, nicht wer dahintersitzt. Wer schon im Trusted-Netz ist, könnte seinem Gerät die Adresse der Workstation von Hand geben. Die Regeln halten also alle anderen Geräte von den Anmeldungen fern. Geschützt sind die Zugänge selbst durch die Anmeldung. SSH geht nur mit Schlüssel und die Weboberflächen von Proxmox und UniFi verlangen zusätzlich einen zweiten Faktor (MFA).

**Sperren und Einschränkungen**

| Regel | Von | Nach | Port | Zweck |
|---|---|---|---|---|
| VPN zu Intern sperren | WireGuard | Intern | alle | kein Weg aus dem VPN zu den eigenen Geräten (UniFi-Standard wäre "alles erlaubt") |
| Homelab zu Gateway DNS | Homelab | Gateway | 53 | DNS |
| Homelab zu Gateway NTP DHCP | Homelab | Gateway | 67, 123 | DHCP für neue Container im Pool, Zeit (NTP) |
| Homelab zu Gateway sperren | Homelab | Gateway | alle | alles andere, auch Weboberfläche und SSH |
| Management zu Gateway DNS | Management | Gateway | 53 | DNS |
| Management zu Gateway Inform | Management | Gateway | 8080 | UniFi-Verwaltung des Access Points |
| Management zu Gateway STUN NTP | Management | Gateway | 123, 3478 | Zeit (NTP), Verbindungsprüfung der UniFi-Verwaltung (STUN) |
| Management zu Gateway sperren | Management | Gateway | alle | alles andere, auch Weboberfläche und SSH |
| Default zu Trusted sperren | Default | Trusted | alle | ein fremdes Gerät ohne VLAN-Tag am AP-Port käme sonst frei an die eigenen Geräte |

Die Sperren gelten nur für neue Verbindungen. Antworten auf erlaubte Verbindungen aus der Gegenrichtung laufen weiter.

**Standard-Sicherheitsstatus "Alle Blockieren":** Neue Netze, Port-Profile und neu aufgenommene UniFi-Geräte starten isoliert. Bestehendes bleibt davon unberührt. Jeder neue Weg muss also bewusst freigegeben werden.


## 🧱 Firewall in Proxmox

Hinter dem Gateway filtert die Proxmox-Firewall als zweite Schicht. Sie ist auf Datacenter- und Host-Ebene aktiv. Jeder Container hat zusätzlich eine eigene Firewall mit `DROP` in beide Richtungen. Ein Container darf also auch nach draußen nur, was ausdrücklich erlaubt ist.

Auch hier stehen keine Adressen in den Regeln, sondern Aliase in `cluster.fw`:

| Alias | Adresse |
|---|---|
| `admin` | `10.0.10.50` (Workstation) |
| `trusted` | `10.0.10.0/24` |
| `vpn` | `192.168.2.0/24` |
| `proxy01` | `10.0.40.10` |
| `cal01` | `10.0.40.30` |
| `ki01` | `10.0.40.50` |
| `mon01` | `10.0.40.90` |
| `pve01` | `10.0.99.10` |

Jede eingehende Regel hat einen Kommentar nach dem Muster "Dienst aus/von Quelle (Zweck)", z. B. `# SSH von admin (Workstation)`. Ausgehende Regeln nennen Dienst und Zweck, z. B. `# HTTP (Updates)`. Die Regeln je Host stehen in der jeweiligen Doku, die Dateien unter [`configs/pve01/firewall/`](../configs/pve01/firewall/).

> Proxmox lässt das eigene lokale Netz (`10.0.99.0/24`) von sich aus auf SSH und Weboberfläche des Hosts. Bewusst so gelassen: Im Management sitzen nur eigene Geräte und das Gateway sperrt den Rest dorthin.


## 📡 VPN

| Option | Value |
|---|---|
| Server | WireGuard im UniFi Gateway |
| Erreichbarkeit | FritzBox reicht per Exposed Host durch, öffentliche Adresse über DynDNS (DuckDNS, gepflegt vom Gateway) |
| VPN-Netz | `192.168.2.0/24`, eigene Zone "VPN" |
| Tunnel | gesamter Verkehr läuft über den Tunnel, DNS über das Gateway (dadurch greift `*.home.<domain>` auch unterwegs) |
| Clients | iPhone, iPad, MacBook mit je eigenem Profil, verbinden sich automatisch außerhalb des eigenen WLANs |
| Erlaubt | nur HTTPS auf `proxy01` |

Teleport, das zweite VPN von UniFi, ist abgeschaltet. Jeder Zugang, den es nicht gibt, muss auch nicht abgesichert werden.


## 📶 WLAN

| WLAN | Netz | Band | Sicherheit |
|---|---|---|---|
| eigene Geräte | Trusted | nur 5 GHz | WPA2/WPA3 |
| Smart-Home | IoT | nur 2,4 GHz | WPA2 |
| Gäste | Gäste | 2,4 + 5 GHz | WPA2/WPA3, Client-Isolation |

Das IoT-WLAN nutzt aus Kompatibilitätsgründen nur 2,4 GHz und reines WPA2. Viele Smart-Home-Geräte unterstützen weder 5 GHz noch WPA3. Das Netz ist über seine Zone ohnehin vom Rest getrennt.

Der Access Point wird über das Management-VLAN verwaltet. Die WLANs und das Management-VLAN hängen getaggt an seinem Port, das native VLAN bleibt Default. Ein Wechsel des nativen VLANs am laufenden Access Point kann ihn von der UniFi-Verwaltung im Gateway trennen. Getaggt lässt er sich ohne dieses Risiko verwalten.


## 📝 Offene Punkte

- Natives VLAN an den Ports dicht machen, damit kein Gerät ohne Tag im Default-Netz landet. Kommt mit dem Switch.
- VPN-Netz aus `192.168.2.0/24` herausnehmen.
- IDS/IPS am Gateway, erst im Meldemodus.
- Radicale-Rückfallweg (Trusted zu cal01) schließen.
- Server untereinander über ihre `.internal`-Namen statt über Adressen ansprechen (Prometheus, Host-Sicherung, Logs).
- Ausgehende Regeln der Container enger fassen: HTTP und HTTPS sind an jedes Ziel erlaubt, auch ins Homelab selbst.
