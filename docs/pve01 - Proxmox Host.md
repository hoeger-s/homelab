# pve01 - Proxmox Host

Stand: 31.08.2026

Basis-Hypervisor des Homelabs. Trägt alle VMs und Container.


## 🖥️ Hardware

| Komponente | Hardware |
|---|---|
| CPU | Intel Core i7-9700K |
| Kerne / Threads | 8 Kerne / 8 Threads |
| RAM | 32 GB DDR4 3200MHz |
| GPU | Zotac RTX 3070 Ti 8GB VRAM |
| Mainboard | ASUS ROG STRIX Z390-I Gaming |
| BIOS | Version 3006 |
| BIOS-Datum | 10-12-2021 |
| Systemlaufwerk | Samsung SSD 970 EVO Plus 256GB NVMe |
| Zusatz-Storage 1 | SanDisk SSD 2TB SATA |
| Zusatz-Storage 2 | WD Blue HDD 2TB SATA |
| Proxmox VE | Version 9 (Debian 13/Trixie) |

> Für die GPU ist Stand 31.08.2026 kein Passthrough konfiguriert - Reserve für später (z. B. KI-Container)


## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | nic0 |
| Hostname | pve01 |
| FQDN | pve01.stefan.lab |
| IP CIDR | 10.0.40.10/24 |
| Gateway | 10.0.40.1 |
| DNS | 10.0.40.1 |
| VLAN | Homelab-VLAN (10.0.40.0/24) |


## 💾 Storage-Layout

| Storage | Medium | Content | Zweck |
|---|---|---|---|
| local | NVMe | ISO, Templates | Proxmox-Install-Default |
| local-lvm | NVMe | - | ungenutzt (Layout-Entscheidung) |
| vm-storage | SATA-SSD, LVM-Thin | Disk Images, Container | aktiver VM-Storage |
| hdd-backup | HDD, ext4 | ISO, Backup, CT-Templates | Backups, ISOs, Templates |

> Trennung OS/VM-Storage/Backup auf drei physische Disks statt gemeinsamer Nutzung der NVMe, um IO-Kontention und Backup-Traffic von System-Boot-Pfad fernzuhalten. Backup liegt aktuell noch lokal auf `hdd-backup` (Single Point of Failure). Langfristig ist eine Auslagerung auf ein externes NAS geplant.

**LVM-Thin config für `vm-storage`:**
```bash
vgcreate vg-vmdata /dev/sda
lvcreate -l 96%FREE -T vg-vmdata/vmdata-thin
```
- Zeroing aktiv (Proxmox-Default)
- Autoextend deaktiviert (Proxmox-Default)
    - `-l 96%FREE` statt `-l 100%FREE` für 4% Headroom in der VG `vg-vmdata`
    - Grafana-Alert `Pve01StoragePoolFull` siehe [mon01 - Monitoring Host](mon01 - Monitoring Host.md)
    - Headroom bei Bedarf per `lvextend` manuell zum Pool hinzufügen


## 🔐 Hardening

- No-Subscription-Repo aktiviert
- Separaten Admin-User mit `sudo`-Rechten und SSH-Key-Auth angelegt
- Root-SSH-Login deaktiviert
- WebUI:
    - dedizierten Admin-User mit Rolle **`Administrator`** angelegt (keine tägliche `root`-Nutzung)
    - Login für `root` und Admin-User mit TOTP-MFA abgesichert
- API-Zugriff für PVE-Exporter (läuft auf `mon01`, siehe Monitoring unten):
    - dedizierter, nur lesender Proxmox-User mit Rolle **`PVEAuditor`** angelegt (Least-Privilege)
    - Zugriff über API-Token statt Passwort
    - "Privilege Separation" deaktiviert (Token erbt direkt die `PVEAuditor`-Rechte)
    - Verbindung ohne SSL-Verifikation (`verify_ssl: false`), da selbstsigniertes Zertifikat
- Proxmox-Firewall (Datacenter und Node) aktiviert, Default-Policy `DROP` (Input), `ACCEPT` (Output)
    - Eingehende Regeln: SSH (Port 22), WebUI (Port 8006) nur aus 10.0.10.0/24
    - API-Zugriff (Port 8006), Node-Exporter-Scrape (Port 9100) und SSH (Port 22) für `mon01` (10.0.40.11/32)


| Direction | Action | Protocol | Port | Source | Zweck |
|---|---|---|---|---|---|
| in | ACCEPT | tcp | 22 | 10.0.10.0/24 | SSH nur aus Trusted-VLAN (Admin) |
| in | ACCEPT | tcp | 8006 | 10.0.10.0/24 | WebUI nur aus Trusted-VLAN (Admin) |
| in | ACCEPT | tcp | 8006 | 10.0.40.11/32 | API-Zugriff für `mon01` (PVE-Exporter) |
| in | ACCEPT | tcp | 9100 | 10.0.40.11/32 | Node-Exporter-Scrape durch `mon01` |
| in | ACCEPT | tcp | 9835 | 10.0.40.11/32 | GPU-Exporter-Zugriff für `mon01` |
| in | ACCEPT | tcp | 22 | 10.0.40.11/32 | SSH von `mon01` für Config-Backup-Transfer, eingeschränkter Key |

> Admin-Zugriff nur aus dem Trusted-VLAN, `mon01`-Zugriff nur von dessen fester IP-Adresse statt dem ganzen Homelab-VLAN.


## 📊 Monitoring

Läuft nativ auf `pve01`, wird von `mon01`s zentralem Prometheus/Grafana-Stack gescraped (automatisch abgefragt).

| Komponente | Version | Port | Zweck |
|---|---|---|---|
| Node-Exporter | 1.12.1 | 9100 | OS-Metriken (CPU, RAM, Disk, Netzwerk) |
| NVIDIA-GPU-Exporter | 1.13.1 | 9835 | GPU-Metriken (Temperatur, Auslastung, VRAM) |

Beide Exporter laufen als eigene systemd-Services mit dediziertem System-User (nicht login-fähig). Der volle Monitoring-Stack (Prometheus/Grafana/Loki/Alertmanager, Alert-Regeln) läuft auf [mon01 - Monitoring Host](mon01 - Monitoring Host.md).

> Voraussetzung für GPU-Exporter: NVIDIA-Treiber `595.91.07` (`--dkms`), `nouveau` geblacklistet, da der Treiber nach einem Reboot sonst nicht lädt.

Zusätzlich läuft ein PVE-Exporter als Docker-Container auf `mon01` und fragt über die Proxmox-API von `pve01` die Proxmox-Verwaltungsebene/Storage-Pools (VM-/Container-Status, Storage-Pool-Auslastung von `local`/`local-lvm`/`vm-storage`/`hdd-backup`) ab. Der Zugriff erfolgt über einen dedizierten `PVEAuditor`-API-Token.


## 📜 Logging (Alloy)

Alloy (v1.19.2) liest lokal das `systemd-Journal` und pusht per `loki.source.journal` an Loki auf `mon01:3100` (Details siehe [mon01 - Monitoring Host](mon01 - Monitoring Host.md)).
Job-Label `systemd-journal` wird per `loki.relabel` erzwungen, sonst überschreibt Alloy es automatisch mit dem Component-Namen.

> Da für Alloy nur ausgehender Traffic entsteht, ist keine Firewall-Änderung notwendig (nicht von Default-DROP-Policy betroffen)


## 💾 Backup

Manuelles `tar`-Archiv von `/etc/pve/`, `/etc/network/interfaces`, `/etc/apt/sources.list.d`, `/etc/ssh/sshd_config`, abgelegt unter `/mnt/hdd-storage/host-backups/pve01-config_<zeitstempel>.tar.gz` (Format `%Y%m%d_%H%M`). Wird bewusst manuell nach nennenswerten Änderungen angestoßen, da der Host aktuell nicht 24/7 läuft.
Kein `vzdump` (Proxmox-Backup-Tool), da dies nur VM-/Container-Storage sichert, nicht die Host-Konfiguration selbst.

**Restore:** Archiv in ein Temp-Verzeichnis entpacken, benötigte Dateien gezielt zurückkopieren. `/etc/pve` ist kein normales Verzeichnis, sondern das virtuelle `pmxcfs`-Dateisystem, Schreibzugriff funktioniert auch im laufenden Betrieb, ohne Dienste zu stoppen. Die drei Dateien außerhalb von `/etc/pve` (Netzwerk, Repos, SSH) brauchen danach einen Reload (`systemctl restart networking`/`sshd`, `apt update`).
Bei komplettem Host-Ausfall: gleiche Wiederherstellung nach einer frischen Proxmox-Installation, erspart das manuelle Nachziehen aller Storage-Definitionen, Firewall-Regeln und User-Rechte.


## 📝 Offene Punkte

- GPU-Passthrough konfigurieren
- Backup auf externes NAS auslagern
- `verify_ssl: false` beim PVE-Exporter ablösen (eigene CA einrichten)
