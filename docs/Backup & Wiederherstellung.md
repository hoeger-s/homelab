# Backup & Wiederherstellung

Stand: 06.11.2026

Wie das Homelab gesichert wird und wie sich Container und Hosts im Ernstfall zurückholen lassen. Was auf dem einzelnen Host im Detail gesichert wird, steht in dessen Doku unter Backup, siehe [pve01 - Proxmox Host](pve01%20-%20Proxmox%20Host.md#-backup) und [mon01 - Monitoring Host](mon01%20-%20Monitoring%20Host.md#-backup).

Grundsatz: Alles, was rund um die Uhr läuft, wird auch automatisch gesichert. Die Sicherung ist so konfiguriert, dass im Ernstfall möglichst wenig von Hand neu einzurichten ist.

Die Sicherung läuft in drei Stufen. Stufe 1 und Stufe 2 laufen, Stufe 3 ist geplant und steht in der Roadmap.


## 📦 Stufe 1 - Container

| Einstellung | Wert |
|---|---|
| Was | alle Container komplett (`vzdump`) |
| Wann | jeden Tag 03:00, verpasste Läufe werden nachgeholt |
| Modus | Snapshot (Container läuft weiter), Kompression zstd |
| Ziel | `hdd-backup` (HDD in `pve01`) |
| Aufbewahrung | 7 Tage, 4 Wochen, 3 Monate |
| Ausnahme | Zwischenspeicher `/root/.cache` in `ki01`, lässt sich komplett neu laden |

Job-Definition: [`configs/pve01/proxmox/jobs.cfg`](../configs/pve01/proxmox/jobs.cfg)

**Warum nicht einfach "die letzten 7 Tage":** Manche Fehler bemerkt man erst nach Tagen oder Wochen. Mit nur sieben Tagessicherungen wäre der letzte gute Stand dann schon weg. So reicht es rund drei Monate zurück, mit höchstens 14 Sicherungen pro Container.

```
heute ─┬─ 7 Tagessicherungen    -> jeden der letzten 7 Tage einzeln
       ├─ 4 Wochensicherungen   -> je eine pro Woche, rund ein Monat
       └─ 3 Monatssicherungen   -> je eine pro Monat, rund drei Monate
```

**Zurückspielen:** Proxmox -> Container -> Backup -> Wiederherstellen, dann starten.

- Die Sicherung ersetzt den bestehenden Container vollständig
- Gibt es den Container nicht mehr, geht es über den Speicher: `hdd-backup` -> Backups -> Wiederherstellen
- Der Container kommt mit den Einstellungen aus der Sicherung zurück, auch mit Adresse und Netzwerk. Hat sich daran seitdem etwas geändert, vor dem Start in Proxmox unter Netzwerk anpassen
- Bei Verdacht auf einen Angriff vorher den aktuellen Stand für eine Analyse sichern und das Backup als geschützt markieren. Das Zurückspielen überschreibt sonst die Spuren und ungeschützte Backups räumt die Aufbewahrung irgendwann weg

> Die Firewall-Regeln eines Containers stecken in seiner Sicherung und kommen beim Zurückspielen mit. Die Aliase, also die Namen für Adressen, auf die sich die Regeln beziehen, stehen aber in `cluster.fw`. Die kommen nur mit der Host-Sicherung von `pve01` (Stufe 2). Snapshots enthalten die Firewall-Regeln nicht.


## 🗂️ Stufe 2 - Host-Konfiguration

Gilt für `pve01` und `mon01`. Container lassen sich mit Stufe 1 komplett zurückspielen, die Hosts selbst nicht. Dort muss im Ernstfall das Betriebssystem neu installiert werden, danach kommt die Konfiguration aus dem Archiv.

| | `pve01` | `mon01` |
|---|---|---|
| Wann | jeden Tag 02:30, verpasste Läufe werden nachgeholt | jeden Tag 02:30, verpasste Läufe werden nachgeholt |
| Wie | Skript mit systemd-Timer | Skript mit systemd-Timer, Übertragung per `scp` auf `pve01` |
| Was | `/etc` komplett, eigene Skripte, SSH-Schlüssel, Paketliste | `/etc` komplett, `/opt/monitoring`, Grafana-Daten, eigene Skripte, SSH-Schlüssel, Paketliste |

Archive: `/mnt/hdd-storage/host-backups/host-<host>-JJJJ_MM_TT-HH_MM_SS.tar.zst`, nur für root lesbar. Die Benennung folgt den Container-Sicherungen, mit `host` statt `vzdump-lxc` und dem Rechnernamen statt der Nummer. Die Aufbewahrung wie bei Stufe 1 übernimmt für beide Hosts das Skript auf `pve01`.

Bewusst nicht gesichert: Messwerte von Prometheus und Logs aus Loki. Die Messwerte zeigen nur Auslastung und Zustand der Hosts, ihre Aufzeichnung beginnt nach einem Ausfall einfach neu. Logs wären vor allem zur Aufklärung von Ausfällen oder Angriffen wichtig. Dafür hilft eine nächtliche Sicherung allerdings wenig. Sie hält nur den Stand von 02:30 Uhr fest. Was danach bis zum Ausfall geschieht, also das Entscheidende, fehlt darin. Außerdem könnte ein Angreifer die Logs schon vor der Sicherung verändert haben. Sinnvoll wäre es also, die Logs laufend an einen getrennten, geschützten Ort zu schicken und dort aufzubewahren. Für dieses Homelab ist das bewusst nicht umgesetzt, weil kein Dienst öffentlich aus dem Internet erreichbar ist. Von außen geht es nur per VPN hinein.

**Was die Skripte absichern:**
- `pve01` bricht ab, wenn die Backup-Platte nicht eingehängt ist. Sonst würde es unbemerkt auf die Systemplatte schreiben
- Auf `pve01` entsteht das Archiv erst als `.partial` und bekommt seinen endgültigen Namen erst, wenn es geprüft ist. Ein halbes Archiv sieht also nie fertig aus. `mon01` prüft sein Archiv, bevor es übertragen wird
- `mon01` hält Grafana für ein paar Sekunden an, damit die Datenbank in sich stimmig gesichert wird. Danach startet das Skript Grafana wieder, auch im Fehlerfall
- Der Schlüssel von `mon01` darf auf `pve01` nur Dateien in den Backup-Ordner schreiben, keine Shell und kein Löschen. Das Aufräumen übernimmt `pve01` selbst
- Beide Skripte lassen sich gefahrlos testen. `DRY_RUN=1` auf `pve01` zeigt nur, was die Aufbewahrung löschen würde. `NO_UPLOAD=1` auf `mon01` lässt das Archiv lokal liegen, statt es zu übertragen

Dateien: [`configs/pve01/host-backup/`](../configs/pve01/host-backup/), [`configs/mon01/host-backup/`](../configs/mon01/host-backup/)

**Zurückspielen:** Archiv in einen leeren Ordner entpacken und nur die benötigten Dateien zurückkopieren. Nicht das ganze Archiv blind über ein laufendes System legen, das würde auch Dateien überschreiben, die seitdem gewollt geändert wurden.

- `/etc/pve` ist kein gewöhnlicher Ordner. Proxmox hält seine Konfiguration in einer eigenen Datenbank und zeigt sie dort nur als Dateien an (Dateisystem `pmxcfs`). Einzelne Dateien lassen sich im laufenden Betrieb zurückkopieren, Proxmox übernimmt sie sofort
- Nach Änderungen an Netzwerk oder SSH den jeweiligen Dienst neu starten, nach Änderungen an den Paketquellen `apt update`
- Nach einer Neuinstallation: erst die Pakete aus der Liste im Archiv (Ordner `_meta`) nachinstallieren, dann die Konfiguration zurückkopieren und anschließend neu starten


## 🌍 Stufe 3 - Kopie außer Haus (geplant)

Stufe 1 und 2 liegen auf der HDD in `pve01`, also im selben Rechner wie die Originale. Das schützt vor einer toten SSD, aber nicht vor Brand, Diebstahl, Überspannung oder einem übernommenen `pve01`.

Geplant ist eine verschlüsselte Sicherung außer Haus. Erst danach kommen Dienste mit wertvolleren Daten dazu, z. B. ein eigener Git-Server.


## 🔧 Snapshots

Vor jedem größeren Umbau bekommt jeder betroffene Container einen Snapshot mit aussagekräftigem Namen (z. B. `vor-update`, `nach-update`). Snapshots liegen auf derselben Platte wie der Container und ersetzen kein Backup. Sie sind der schnelle Rückweg, falls ein Schritt schiefgeht oder sich eine Einstellung als Fehler herausstellt.


## 📝 Offene Punkte

- Stufe 3, verschlüsselte Kopie außer Haus
- Alert, wenn eine Sicherung fehlschlägt oder älter als ein Tag ist. Heute fällt ein Fehler nur im Journal auf
- Abgebrochene Übertragung von `mon01` erkennbar machen. Heute liegt dann auf `pve01` ein halbes Archiv, das vollständig aussieht
- Eine Wiederherstellung einmal komplett durchspielen und dokumentieren
