# pve01 - Proxmox Host

Stand: 26.10.2026

Basis-Hypervisor des Homelabs. Trägt aktuell alle Container und künftig auch die VMs, Übersicht siehe [Host, VM- und Container-Übersicht](Host,%20VM-%20und%20Container-%C3%9Cbersicht.md). `pve01` läuft rund um die Uhr und startet nach einem Stromausfall per BIOS-Einstellung wieder von selbst.


## 🖥️ Hardware

| Komponente | Hardware |
|---|---|
| CPU | Intel Core i7-9700K |
| Kerne / Threads | 8 Kerne / 8 Threads |
| RAM | 32 GB DDR4 3200 MHz |
| GPU | Zotac RTX 3070 Ti 8 GB VRAM |
| Mainboard | ASUS ROG STRIX Z390-I Gaming |
| BIOS | Version 3006 (12.10.2021) |
| Systemlaufwerk | Samsung SSD 970 EVO Plus 256 GB NVMe |
| Zusatz-Storage 1 | SanDisk SSD 2 TB SATA |
| Zusatz-Storage 2 | WD Blue HDD 2 TB SATA |
| Proxmox VE | Version 9 (Debian 13/Trixie) |

> Die GPU wird per Device-Freigabe (`devX`, Proxmox 9) an einen Container durchgereicht, kein VM-Passthrough.


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | `nic0` -> Bridge `vmbr0` (VLAN-aware) |
| Hostname | pve01 |
| FQDN | pve01.internal |
| IP CIDR | 10.0.99.10/24 |
| Gateway | 10.0.99.1 |
| DNS | 10.0.99.1, Suchdomäne `internal` |
| VLAN | Management (VLAN 99), Container im Homelab (VLAN 40) |
| Switchport | Port 2, Profil pve01-Trunk (nativ Management, getaggt Homelab) |
| Weboberfläche | `https://10.0.99.10:8006` bzw. `https://pve01.internal:8006` |

Der Host selbst sitzt im Management-VLAN, die Container im Homelab-VLAN. Möglich macht das eine VLAN-fähige Bridge. Der Port zum Gateway ist ein Trunk und jeder Container bekommt in seiner Netzwerkkonfiguration `tag=40`. Die Bridge reicht die Pakete nur durch. Aus dem Homelab ist der Host damit nicht ansprechbar, da er dort keine eigene Adresse hat. Wer aus dem Homelab zum Host will, muss über das Gateway und dort ist per Firewall nur freigegeben, was `mon01` für Monitoring und Sicherung braucht.

> Diese Trennung gilt nur auf Netzwerkebene. Container teilen sich den Kernel des Betriebssystems mit dem Host. Über eine Sicherheitslücke im Kernel könnte man also aus einem Container auf den Host ausbrechen, ganz ohne Umweg übers Netz. Meine Container laufen deshalb zusätzlich unprivilegiert. Wer im Container `root` ist, hat auf dem Host keinerlei Rechte und kommt an viele Funktionen des Kernels gar nicht erst heran. Einen solchen Ausbruch verhindert das aber nicht sicher. Deutlich stärker getrennt sind VMs, da sie einen eigenen Kernel mitbringen.

```bash
# /etc/network/interfaces (Ausschnitt)
auto vmbr0
iface vmbr0 inet static
        address 10.0.99.10/24
        gateway 10.0.99.1
        bridge-ports nic0
        bridge-stp off
        bridge-fd 0
        bridge-vlan-aware yes
        bridge-vids 2-4094
```

```bash
# Netzwerkzeile eines Containers, hier proxy01
net0: name=eth0,bridge=vmbr0,firewall=1,gw=10.0.40.1,ip=10.0.40.10/24,tag=40,type=veth
```

Komplette Datei: [`configs/pve01/network/interfaces`](../configs/pve01/network/interfaces)


## 💾 Storage-Layout

| Storage | Medium | Content | Zweck |
|---|---|---|---|
| local | NVMe | ISO, CT-Templates, Backup, Import | Proxmox-Install-Default |
| local-lvm | NVMe | Disk Images, Container | ungenutzt (Layout-Entscheidung) |
| vm-storage | SATA-SSD, LVM-Thin | Disk Images, Container | aktiver Storage für Container und VMs |
| hdd-backup | HDD, ext4 | ISO, Backup, CT-Templates | Backups, ISOs, Templates |

> Trennung von System, Containern und Backups auf drei physische Platten, damit Backup-Traffic und Container nicht mit dem System um dieselbe Platte konkurrieren. Alle Sicherungen, also Container und Host-Konfiguration, landen auf `hdd-backup`. Dass `local` auch Backups erlaubt, ist eine Voreinstellung von Proxmox. Die Backups liegen damit aber noch im selben Rechner wie die Originale (Single Point of Failure). Eine Kopie außer Haus ist bereits geplant. Details siehe [Backup & Wiederherstellung](Backup%20&%20Wiederherstellung.md).

**LVM-Thin config für `vm-storage`:**
```bash
vgcreate vg-vmdata /dev/sda
lvcreate -l 96%FREE -T vg-vmdata/vmdata-thin
```
- Zeroing aktiv (Proxmox-Default)
- Autoextend deaktiviert (Proxmox-Default)
    - `-l 96%FREE` statt `-l 100%FREE` für 4 % Reserve in der Volume Group (VG) `vg-vmdata`
    - Alert `Pve01StoragePoolFull` ab 85 %, siehe [mon01 - Monitoring Host](mon01%20-%20Monitoring%20Host.md)
    - Reserve bei Bedarf per `lvextend` manuell zum Pool hinzufügen

Konfiguration: [`configs/pve01/proxmox/storage.cfg`](../configs/pve01/proxmox/storage.cfg)


## 🔐 Hardening

- No-Subscription-Repo aktiviert
- Separater Admin-User mit `sudo` und SSH-Key
- Root- und Passwort-Login per SSH deaktiviert
- WebUI:
    - eigener Admin-User mit Rolle **`Administrator`** angelegt (keine tägliche `root`-Nutzung)
    - Login für `root` und Admin-User mit Multi-Faktor-Authentifizierung (MFA) per Time-based One-Time Password (TOTP)
- API-Zugriff für den PVE-Exporter auf `mon01`:
    - eigener, nur lesender User mit Rolle **`PVEAuditor`** (Least-Privilege)
    - Zugriff über API-Token statt Passwort
    - "Privilege Separation" deaktiviert (Token erbt genau die `PVEAuditor`-Rechte)
    - Verbindung ohne SSL-Verifikation (`verify_ssl: false`), da selbstsigniertes Zertifikat
- Proxmox-Firewall auf Datacenter- und Host-Ebene aktiv, Default-Policy `DROP` (Input), `ACCEPT` (Output)
    - Jeder Container hat eine eigene Firewall mit `DROP` in beide Richtungen

**Regeln (`cluster.fw`):**

| Direction | Action | Protocol | Port | Source | Zweck |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 22 | `admin` | SSH nur von der Workstation |
| in | ACCEPT | tcp | 8006 | `admin` | Weboberfläche nur von der Workstation |
| in | ACCEPT | tcp | 22 | `mon01` | Host-Sicherung von `mon01`, eingeschränkter Schlüssel |
| in | ACCEPT | tcp | 8006 | `mon01` | API für den PVE-Exporter |
| in | ACCEPT | tcp | 9100 | `mon01` | Node-Exporter |
| in | ACCEPT | tcp | 9835 | `mon01` | GPU-Exporter |

Quellen sind Aliase, die Adressen stehen nur einmal im Block `[ALIASES]` derselben Datei (siehe [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md#-firewall-in-proxmox)). Davor sitzt noch das Gateway mit eigenen Regeln für dieselben Wege.

Regeldateien: [`configs/pve01/firewall/`](../configs/pve01/firewall/)

> Die Firewall-Dateien liegen auf dem Host unter `/etc/pve/firewall/`, nicht in den Containern. Container-Snapshots und Container-Backups enthalten sie also nicht. Gesichert werden sie mit der Host-Sicherung von `pve01`.


## 📊 Monitoring

Läuft nativ auf `pve01`, Prometheus auf `mon01` fragt die Werte ab (Scraping). Der komplette Monitoring-Stack mit Alert-Regeln ist in [mon01 - Monitoring Host](mon01%20-%20Monitoring%20Host.md) beschrieben.

| Komponente | Version | Port | Zweck |
|---|---|---|---|
| Node-Exporter | 1.12.1 | 9100 | OS-Metriken (CPU, RAM, Disk, Netzwerk) |
| NVIDIA-GPU-Exporter | 1.13.1 | 9835 | GPU-Metriken (Temperatur, Auslastung, VRAM) |

Beide Exporter laufen als eigene systemd-Services mit dediziertem System-User ohne Login. Zusätzlich fragt der PVE-Exporter auf `mon01` über die Proxmox-API den Status der Container und VMs sowie die Auslastung der Storage-Pools ab.

> Voraussetzung für den GPU-Exporter: NVIDIA-Treiber `595.91.07` (`--dkms`), `nouveau` geblacklistet, da sonst der Treiber nach einem Reboot nicht lädt.


## 📜 Logging (Alloy)

Alloy (v1.19.2) liest das systemd-Journal und schickt es an Loki auf `mon01` (`10.0.40.90:3100`). Jeder Eintrag bekommt die Labels `host`, `job`, `unit` (welcher Dienst) und `level` (Schweregrad). Damit lässt sich in Grafana z. B. gezielt nach allen Fehlern eines Dienstes filtern.

Von sich aus vergibt Alloy nur ein Label, `job`, mit dem Namen des Bausteins. Die versteckten Zusatzfelder des Journals, etwa welcher Dienst eine Meldung geschrieben hat und wie ernst sie ist, verwirft Alloy dagegen, bevor es die Einträge an Loki schickt. Was davon ankommen soll, muss ausdrücklich als Label festgelegt werden. Übernommen werden nur Dienst (`unit`) und Schweregrad (`level`). Dazu kommt das fest gesetzte `host`. `job` erhält einen lesbaren Namen. Mehr wird bewusst nicht mitgenommen, denn Loki legt für jede Kombination von Labels einen eigenen Datenstrom an. Je mehr Labels, desto mehr Datenströme und desto langsamer wird Loki. Die Suche in Grafana würde dann zäh. Im schlimmsten Fall nimmt Loki gar keine neuen Einträge mehr an.

Technisch: Die Regeln stehen in einem `loki.relabel`-Block. Dieser läuft aber nicht als eigener Schritt hinter dem Einlesen, denn dort wären Dienst und Schweregrad schon weg. Stattdessen übergibt `relabel_rules` die Regeln direkt an `loki.source.journal`, das sie beim Einlesen selbst anwendet.

Konfiguration: [`configs/pve01/alloy/config.alloy`](../configs/pve01/alloy/config.alloy)

> Für Alloy entsteht nur ausgehender Traffic, auf `pve01` ist dafür keine Firewall-Regel nötig. Im Gateway braucht es die Regel "pve01 zu mon01" (Port 3100), auf `mon01` die passende `ufw`-Freigabe.


## 💾 Backup

- **Container:** Job "Container taeglich" in Proxmox (`vzdump`), jeden Tag 03:00, alle Container. Aufbewahrung 7 Tage, 4 Wochen, 3 Monate (je Tag, Woche und Monat bleibt der neueste Stand). Job-Definition: [`configs/pve01/proxmox/jobs.cfg`](../configs/pve01/proxmox/jobs.cfg)
- **Host-Konfiguration:** Skript mit systemd-Timer, jeden Tag 02:30, gleiche Aufbewahrung. Eigenes Skript, weil `vzdump` nur Container und VMs sichert, nicht die Konfiguration des Hosts selbst. Gesichert werden:
    - `/etc` komplett (inkl. `/etc/pve` mit Firewall und Jobs) statt einzelner Dateien, damit im Ernstfall möglichst wenig von Hand nachzuziehen ist. Das Archiv ist trotzdem nur rund 600 KB groß.
    - eigene Skripte aus `/usr/local/sbin`, darunter das Sicherungsskript selbst
    - die SSH-Schlüssel von `root` und Admin-User
    - eine Liste aller installierten Pakete samt Version, damit sich der Host nach einer Neuinstallation wieder auf denselben Stand bringen lässt

  Dateien: [`configs/pve01/host-backup/`](../configs/pve01/host-backup/)

- **Sicherung von `mon01`:** `mon01` legt seine Host-Sicherung jede Nacht per `scp` auf der Backup-Platte von `pve01` ab. Dafür ist SSH von `mon01` in der Firewall freigegeben (Port 22, siehe Regeln oben). Alte Archive von `mon01` räumt das Skript von `pve01` mit auf.

Alles Weitere, auch zur Wiederherstellung: [Backup & Wiederherstellung](Backup%20&%20Wiederherstellung.md)


## 📝 Offene Punkte

- Kopie der Backups außer Haus
- `verify_ssl: false` beim PVE-Exporter ablösen, sobald es eine interne CA gibt
- Zertifikat der Weboberfläche ist selbst signiert, wird mit der internen CA ersetzt
- Ausstehende Updates einspielen
