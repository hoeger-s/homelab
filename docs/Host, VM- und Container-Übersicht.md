# Host-Übersicht

| Name | Rolle | OS | CPU | RAM | Storage | Domain | IP-Adresse | Netz | Notizen |
|---|---|---|---|---|---|---|---|---|---|
| `pve01` | Proxmox-Hypervisor | Proxmox VE9 | 8c/8t | 32 GB | 256 GB NVMe, 2 TB SSD, 2 TB HDD | `stefan.lab` | `10.0.40.10` | Homelab (`10.0.40.0/24`) | Main Host |
| `mon01` | Monitoring | Debian 13 (trixie) | 2c/4t | 16 GB | 240 GB NVMe | `stefan.lab` | `10.0.40.11` | Homelab (`10.0.40.0/24`) | Monitoring Host |


# VM- und Container-Übersicht

| Name | Host | VMID/CTID | OS | Zweck | Typ | Domain | IP-Adresse | Netz | vCPU | RAM | Disk | Status | Notizen |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `argus-fw-edge` | `pve01` | 101 | pfSense CE | Edge-Firewall | VM | argus.lab | WAN `10.0.40.12`, LAN `10.0.100.1` | Homelab-VLAN (WAN) / Mgmt `10.0.100.0/24` (LAN) | 2 | 2048 MB | 20 GB | Running | - |
