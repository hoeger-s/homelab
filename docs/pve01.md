# pve01 - Proxmox Host

Stand: 23-08-2026

Basis-Hypervisor und Startpunkt für ARGUS. Trägt alle VMs/Container.

## 🖥️ Hardware

| Komponente | Hardware |
|---|---|
| CPU | Intel Core i7-9700K |
| Kerne / Threads | 8 Kerne / 8 Threads |
| RAM | 32 GB DDR4 3200mhz |
| GPU | Zotac RTX 3070 Ti 8GB VRAM |
| Mainboard | AUSUS ROG STRIX Z390-I Gaming |
| BIOS | Version 3006 |
| BIOS-Datum | 10-12-2021 |
| Systemlaufwerk | Samsung SSD 970 EVO Plus 256GB NVMe |
| Zusatz-Storage 1 | SanDisk SSD 2TB SATA |
| Zusatz-Storage 2 | WD Blue HDD 2TB SATA |

> Für die GPU ist Stand 14-08-2026 kein Passthrough konfiguriert - Reserve für später (z. B. Ki-Container)

## 🌐 Netzwerk

| Option | Value |
|---|---|
| Interface | eno1 |
| Hostname| pve01 |
| FQDN | pve01.argus.lab |
| IP CIDR | 192.168.178.10/24 |
| Gateway | 192.168.178.1 |
| DNS Server | 192.168.178.1 |


## 💾 Storage-Layout

| Storage | Medium | Content | Zweck |
|---|---|---|---|
| local | NVMe | ISO, Templates | Proxmox-Install-Default |
| local-lvm | NVMe | - | ungenutzt (Layout-Entscheidung) |
| vm-storage | SATA-SSD, LVM-Thin | Disk Images, Container | aktiver VM-Storage |
| hdd-backup | HDD, ext4 | ISO, Backup, CT-Templates | Backups, ISOs, Templates |

> Trennung OS/VM-Storage/Backup auf drei physische Disks statt gemeinsamer Nutzung der NVMe, um I/O-Kontention und Backup-Traffic vom System-Boot-Pfad fernzuhalten.

## 🔐 Hardening

- No-Subscription-Repo aktiv
- Root-SSH-Login deaktiviert, Zugriff über separat angelegten Admin-Account + SSH-Key, sudo
- Proxmox-Firewall aktiv (Datacenter + Node), Default-Policy DROP
- Eingehende Regeln: SSH (Port 22) und WebUI (Port 8006) nur aus 192.168.178.0/24
- WebUI-Root-Login mit 2FA abgesichert

## 📜 Logging (Alloy)

Alloy 1.18.1 liest lokal das systemd-Journal und pusht es an Loki auf `mon01:3100` (Details siehe [mon01 - Monitoring-Container](mon01.md)).

> Keine Firewall-Änderung auf `pve01` nötig, da nur ausgehender Traffic entsteht. Nicht von der Default-DROP-Policy betroffen.

## ✅ Verifikation

Test-VM (VID 100) angelegt zur End-to-End-Prüfung:

- Disk korrekt auf vm-storage (LVM-Thin) platziert
- Boot von ISO auf hdd-backup funktioniert (Boot-Order muss CD-ROM explizit enthalten: order=ide2;scsi0)
- Netzwerk-Bridging über vmbr0 funktionsfähig (IP-Bezug im Installer bestätigt)
- VM nach Test wieder entfernt (qm destroy 100)

## 📝 Offene Punkte

- LVM-Thin-Feintuning (Übercommit-Verhalten, Monitoring der Pool-Auslastung)
- Dedizierter WebUI-User inkl. 2FA mit eingeschränkten Rechten
