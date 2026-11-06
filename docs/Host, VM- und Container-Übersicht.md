# Host, VM- und Container-Übersicht

Stand: 06.11.2026

Alle Rechner, Container und Netzwerkgeräte des Homelabs auf einen Blick. Details stehen in der Doku des jeweiligen Hosts, Netze und Firewall-Regeln unter [Netzwerk & Sicherheit](Netzwerk%20&%20Sicherheit.md).


# Hosts

| Name | Rolle | OS | CPU | RAM | Storage | FQDN | IP-Adresse | Netz | Notizen |
|---|---|---|---|---|---|---|---|---|---|
| `pve01` | Proxmox-Hypervisor | Proxmox VE 9 | 8c/8t | 32 GB | 256 GB NVMe, 2 TB SSD, 2 TB HDD | `pve01.internal` | `10.0.99.10` | Management (`10.0.99.0/24`) | trägt alle Container, siehe [pve01 - Proxmox Host](pve01%20-%20Proxmox%20Host.md) |
| `mon01` | Monitoring | Debian 13 (trixie) | 2c/4t | 16 GB | 240 GB M.2 SATA | `mon01.internal` | `10.0.40.90` | Homelab (`10.0.40.0/24`) | Intel NUC, siehe [mon01 - Monitoring Host](mon01%20-%20Monitoring%20Host.md) |


# Container

Alle Container laufen auf `pve01`, unprivilegiert und per VLAN-Tag 40 im Homelab.

| Name | CTID | OS | Zweck | Typ | FQDN | IP-Adresse | vCPU | RAM | Disk | Notizen |
|---|---|---|---|---|---|---|---|---|---|---|
| `proxy01` | 120 | Debian 13 (trixie) | Reverse Proxy | LXC | `proxy01.internal` | `10.0.40.10` | 1 | 512 MB | 4 GB | Wildcard-Zertifikat `*.home.<domain>`, siehe [proxy01 - Reverse Proxy](proxy01%20-%20Reverse%20Proxy.md) |
| `cal01` | 121 | Debian 13 (trixie) | Kalender Server | LXC | `cal01.internal` | `10.0.40.30` | 1 | 512 MB | 8 GB | Radicale, erreichbar über `cal.home.<domain>`, siehe [cal01 - Kalender Server](cal01%20-%20Kalender%20Server.md) |
| `ki01` | 110 | Debian 13 (trixie) | KI-Assistent | LXC | `ki01.internal` | `10.0.40.50` | 4 | 12 GB | 288 GB | nutzt die GPU von `pve01`. Eigenes Projekt, hier nur der Vollständigkeit halber |

Startreihenfolge nach `pve01`: `proxy01`, dann `cal01`, dann `ki01`. Begründung in den Docs von [proxy01](proxy01%20-%20Reverse%20Proxy.md) und [cal01](cal01%20-%20Kalender%20Server.md).


# VMs

Aktuell keine. VMs kommen zu einem späteren Zeitpunkt.


# Netzwerkgeräte

| Name | Rolle | IP-Adresse | Netz | Notizen |
|---|---|---|---|---|
| FritzBox | Kabelmodem | - | vor dem Gateway | nur Übergabe zum Kabelanbieter, WLAN, Portfreigaben und Fernzugriff aus |
| UniFi Cloud Gateway Ultra | Router, Firewall, DNS, VPN | `.1` in jedem VLAN | alle | - |
| U7 Lite | Access Point | `10.0.99.3` | Management (`10.0.99.0/24`) | Verwaltung getaggt im VLAN 99 |
