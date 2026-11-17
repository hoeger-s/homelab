# Updates & Patchmanagement

Stand: 17.11.2026

Wie Hosts, Container, Docker-Images und Netzwerkgeräte des Homelabs aktuell gehalten werden. Welche Pakete und Versionen auf dem einzelnen Host laufen, steht in dessen Doku.

Updates werden nach Risiko getrennt. Sicherheitsupdates der Debian-Systeme laufen automatisch. Alles andere wird einmal im Monat am Patchday von Hand eingespielt, mit Snapshot davor und Prüfung danach. Was beim Update kaputtgehen kann, wird nicht unbeaufsichtigt aktualisiert. Einzige Ausnahme sind Gateway und Access Point, siehe unten.


## 🗓️ Überblick

| Was | Wie | Wann |
|---|---|---|
| Sicherheitsupdates der Container und von `mon01` | automatisch (`unattended-upgrades`), betroffene Dienste starten neu, `mon01` bei neuem Kernel ganz | täglich nach der Sicherung |
| alle übrigen Pakete der Container und von `mon01` | von Hand | Patchday |
| Docker-Images auf `mon01` | von Hand, feste Versionen | Patchday |
| `pve01` (Proxmox, Kernel, GPU-Treiber) | nur von Hand | Patchday |
| Firmware und Network-Anwendung von Gateway und Access Point | automatisch, nur offizieller Kanal | nachts |
| kritische Sicherheitslücken | von Hand | sofort, außer der Reihe |


## 🤖 Automatische Sicherheitsupdates

Auf den Containern und auf `mon01` läuft `unattended-upgrades`. Es installiert jeden Tag nur Pakete aus dem Sicherheits-Repo von Debian (`trixie-security`). Die Debian-Sicherheitsupdates beheben gezielt Sicherheitslücken und ändern sonst nichts am Verhalten eines Programms. Deshalb ist das Risiko gering, dass ein automatisches Update einen Dienst stört. Die Point-Releases von Debian, also Zwischenstände wie 13.1 oder 13.2 mit gesammelten Fehlerkorrekturen, spielt `unattended-upgrades` von Haus aus ebenfalls ein. Diese sind hier abgeschaltet und kommen am Patchday von Hand.

| Schritt | Uhrzeit |
|---|---|
| Paketlisten laden (`apt-daily`) | 04:45 |
| Sicherheitsupdates einspielen (`apt-daily-upgrade`) | 05:00 |

Die Updates laufen bewusst nach der nächtlichen Sicherung der Hosts (02:30) und der Container (03:00). Der Stand direkt vor einem Update ist somit immer gesichert, sollte mal etwas schiefgehen. Die Uhrzeiten stehen in Drop-ins (kleine Ergänzungsdateien). Diese überschreiben einzelne Einstellungen der systemd-Units von Debian, ohne die Originaldatei zu ändern. Die übliche zufällige Verzögerung ist abgeschaltet, damit die Reihenfolge nach der Sicherung sicher bleibt. War ein System um 05:00 aus, holt es den Lauf beim nächsten Start nach.

**Neustarts:** Nach einem Update startet `needrestart` die Dienste neu, die noch die alten Bibliotheken geladen haben. Ohne das liefen sie bis zum nächsten Neustart mit der alten Version weiter. Einen Neustart des ganzen Systems brauchen die Container nicht, da sie keinen eigenen Kernel haben und den des Hosts nutzen. Kommt auf `mon01` ein neuer Kernel, startet `mon01` direkt nach dem Update selbst neu. Die Container des Monitoring-Stacks kommen danach von alleine wieder hoch.

**Kein Warten aufs Netz in den Containern:** Vor jedem Lauf wartet apt standardmäßig, bis `systemd-networkd` das Netz als verbunden meldet. In den Containern richtet Proxmox das Netz ein. `systemd-networkd` läuft dort zwar mit, ist für das Netz aber nicht zuständig und meldet deshalb nie "verbunden". apt bricht das Warten nach 30 Sekunden mit einer Fehlermeldung im Journal ab und spielt die Updates trotzdem ein. Damit das Journal sauber bleibt, streicht in den Containern je ein Drop-in für `apt-daily` und `apt-daily-upgrade` diesen Warteschritt. `mon01` braucht das nicht.

**Bewusst nicht automatisch:**

- Pakete aus fremden Repos, etwa Docker auf `mon01` und Caddy auf `proxy01`. Sie bringen mit neuen Versionen auch neue Funktionen und geänderte Einstellungen mit
- die Docker-Images des Monitoring-Stacks, siehe unten
- `pve01` selbst, siehe unten

| Datei | Zweck |
|---|---|
| `apt.conf.d/20auto-upgrades` | schaltet die täglichen Läufe ein |
| `apt.conf.d/52unattended-upgrades-homelab` | nur `trixie-security`, auf `mon01` zusätzlich der Neustart bei neuem Kernel |
| `needrestart/conf.d/50-homelab.conf` | betroffene Dienste ohne Rückfrage neu starten |
| `systemd/apt-daily.timer.d/`, `systemd/apt-daily-upgrade.timer.d/` | Uhrzeiten |
| `systemd/apt-daily.service.d/`, `systemd/apt-daily-upgrade.service.d/` | kein Warten auf `systemd-networkd` (nur Container) |

Die Debian-Datei `50unattended-upgrades` bleibt unverändert. Die eigenen Einstellungen stehen in einer eigenen Datei daneben, so überschreibt ein Update von `unattended-upgrades` sie nicht.

Konfiguration: [`configs/<host>/auto-updates/`](../configs/)

Was zuletzt automatisch installiert wurde, steht in `/var/log/unattended-upgrades/` auf dem jeweiligen System. Ob dabei Fehler aufgetreten sind, zeigt das Journal (`journalctl -u apt-daily-upgrade`).


## 📅 Patchday

Einmal im Monat, fester Termin am ersten Sonntag.

1. **Vorher lesen:** Änderungshinweise von Proxmox und den Docker-Images überfliegen. Gesucht sind Hinweise auf geänderte Einstellungen oder bekannte Probleme. Bei UniFi nur nachsehen, ob Gateway und Access Point aktuell sind
2. **Snapshot:** Jeder Container bekommt einen Snapshot `vor-update-JJJJ-MM`
3. **Container:** `apt update`, dann `apt full-upgrade`. Erst `cal01`, dann `proxy01`. Auf `proxy01` zusätzlich `caddy upgrade`, denn der eigene Caddy-Build ist von apt ausgenommen
4. **`mon01`:** Pakete wie bei den Containern, Neustart, danach die Docker-Images. Anschließend `ki01`
5. **`pve01`:** Zuletzt, siehe unten. Sein Neustart fährt alle Container herunter und wieder hoch
6. **Prüfen:** Kalender auf dem iPhone synchronisiert, Grafana zeigt aktuelle Werte und Logs, alle Prometheus-Targets sind `UP`
7. **Aufräumen:** Die Snapshots bleiben eine Woche stehen. Ist bis dahin nichts aufgefallen, werden sie gelöscht

**Warum `pve01` zuletzt:** Ein Container, den ein Update beschädigt, ist per Snapshot in einer Minute zurück. Für `pve01` gibt es keinen Snapshot. Geht dort etwas schief, sollen wenigstens alle Container schon auf dem neuen Stand und geprüft sein.

**Versionssprünge:** Wechsel auf eine neue Hauptversion, etwa Debian 13 auf 14, Proxmox VE 9 auf 10 oder Grafana 13 auf 14, gehören nicht in den Patchday. Sie bekommen einen eigenen Termin.


## 🖥️ `pve01`

`pve01` wird nie automatisch aktualisiert. Ein Update kann hier den Kernel tauschen und damit den GPU-Treiber treffen.

Aktualisiert wird mit `apt full-upgrade`, nie mit `apt upgrade`. Nur so kommen Updates mit, die neue Pakete nachziehen oder alte entfernen, etwa ein neuer Kernel.

**Kernel und GPU-Treiber:** Der NVIDIA-Treiber stammt nicht aus Debian, sondern aus NVIDIAs eigenem Installer. Er ist mit `--dkms` installiert. DKMS baut das Treibermodul für jeden neuen Kernel automatisch neu, braucht dafür aber die passenden Kernel-Header. Die bringt das Paket `proxmox-default-headers` zu jedem neuen Kernel mit. Fehlen sie, scheitert der Neubau still. Nach dem Neustart ist die GPU dann weg.

Deshalb vor dem Neustart prüfen, ob das Modul für den neuen Kernel gebaut ist:

```bash
dkms status     # nvidia/595.91.07, <neuer Kernel>, x86_64: installed
```

Nach dem Neustart zeigt `nvidia-smi` die GPU. Die Container mit GPU haben dann wieder Zugriff.

**Treiberversion:** Container, die die GPU nutzen, bringen den Treiber ohne Kernelmodul selbst mit. Er muss exakt dieselbe Version haben wie auf `pve01`. Ein neuer Treiber wird deshalb nie nebenbei installiert, sondern immer auf `pve01` und in den betroffenen Containern im selben Zug.

**Rückweg:** Der vorherige Kernel bleibt installiert und lässt sich beim Start im Bootmenü auswählen. Diese Auswahl gilt aber nur für den einen Start. Damit `pve01` bis zur Lösung eines Problems immer mit dem alten Kernel startet, wird er festgehalten (gepinnt) und danach wieder freigegeben.

```bash
proxmox-boot-tool kernel pin <version>  # festhalten
proxmox-boot-tool kernel unpin          # wieder freigeben
```


## 🐳 Docker-Images auf `mon01`

Jedes Image steht in der [`docker-compose.yml`](../configs/mon01/monitoring/docker-compose.yml) mit fester Versionsnummer, nie mit `latest`. Mit `latest` holt jedes `docker compose pull` stillschweigend die neuste Version. Welche gerade läuft, ist dann nicht mehr nachvollziehbar.

Am Patchday je Image:

1. Neue Version und Änderungshinweise ansehen. Bei Grafana und Loki besonders auf geänderte Einstellungen achten
2. Versionsnummer auf `mon01` in der `docker-compose.yml` anheben
3. `docker compose pull`, dann `docker compose up -d`
4. Prüfen, ob der Container läuft und Grafana Daten zeigt
5. Geänderte `docker-compose.yml` ins Repo übernehmen

**Rückweg:** alte Versionsnummer eintragen und `docker compose up -d`. Für `mon01` gibt es keinen Snapshot, die Daten von Grafana kommen notfalls aus der Host-Sicherung der Nacht, siehe [Backup & Wiederherstellung](Backup%20&%20Wiederherstellung.md).


## 📶 Gateway und Access Point

Gateway und Access Point aktualisieren sich nachts selbst, nur aus dem offiziellen Kanal und ohne Vorabversionen (Early Access). Das Gateway ist aus dem Internet erreichbar, der Access Point für jeden in Funkreichweite. Lücken sollen dort so schnell wie möglich geschlossen werden, auch wenn ein Update einmal fehlerhaft sein kann.

UniFi erstellt wöchentlich automatisch ein Backup. Vor größeren Änderungen kommt ein Backup von Hand dazu, das auf der Workstation abgelegt wird. Der Access Point kann nach einem Update zur vorherigen Firmware zurückkehren. Am Patchday wird nur nachgesehen, ob beide aktuell sind.


## 🚨 Kritische Lücken außer der Reihe

Wird eine Lücke aktiv ausgenutzt oder trifft sie eine Komponente, die von außen erreichbar ist, wartet sie nicht auf den Patchday. Das betrifft vor allem das Gateway mit dem WireGuard-Port und den Reverse Proxy. Der Ablauf bleibt derselbe, nur für die betroffenen Systeme.

Quellen sind die Sicherheitsmeldungen von Debian, Proxmox und UniFi.


## 📝 Offene Punkte

- Meldung, wenn automatische Updates fehlschlagen oder Updates länger als einen Monat offen sind
- Zahl der offenen Updates je Host im Dashboard "Homelab Overview"
- Hinweis auf kritische Sicherheitslücken in den eingesetzten Diensten, ohne dass man selbst die Meldungen verfolgen muss
