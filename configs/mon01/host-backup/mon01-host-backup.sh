#!/bin/bash
# Taegliche Sicherung der Host-Konfiguration von mon01 (Backup-Konzept Stufe 2)
# Archiv: host-mon01-JJJJ_MM_TT-HH_MM_SS.tar.zst, per scp nach pve01:/mnt/hdd-storage/host-backups/
# Aufbewahrung 7/4/3 uebernimmt pve01 (der Schluessel darf dort nur schreiben).
# Test ohne Uebertragung: NO_UPLOAD=1 /usr/local/sbin/mon01-host-backup.sh  (Archiv bleibt in /var/tmp)
set -euo pipefail
shopt -s nullglob

HOST="mon01"
TARGET="<admin-user>@10.0.99.10"                     # pve01 (Management-VLAN seit Phase 5, 22.10.2026)
SSH_DIR="/home/<admin-user>/.ssh"
KEY="$SSH_DIR/pve01-backup"                        # erzwingt dort: scp -t /mnt/hdd-storage/host-backups/
GRAFANA_CONTAINER="grafana"
GRAFANA_VOLUME="monitoring_grafana-data"

log() { logger -t host-backup "$*"; echo "$*"; }
fail() { log "FEHLER: $*"; exit 1; }

# Was gesichert wird (relativ zu /)
cd /
PATHS=()
for p in etc opt/monitoring usr/local/bin usr/local/sbin root/.ssh home/*/.ssh; do
  [[ -e $p ]] && PATHS+=("$p")
done
VOL=$(docker volume inspect -f '{{.Mountpoint}}' "$GRAFANA_VOLUME") || fail "Volume $GRAFANA_VOLUME nicht gefunden"
PATHS+=("${VOL#/}")

TS=$(date +%Y_%m_%d-%H_%M_%S)
TMP=$(mktemp -d /var/tmp/host-backup.XXXXXX)
OUT="$TMP/host-$HOST-$TS.tar.zst"
GRAFANA_STOPPED=0
cleanup() {
  if (( GRAFANA_STOPPED )); then docker start "$GRAFANA_CONTAINER" >/dev/null || log "FEHLER: Grafana startet nicht"; fi
  if [[ "${NO_UPLOAD:-0}" != 1 ]]; then rm -rf "$TMP"; fi
}
trap cleanup EXIT

# Paketliste und laufende Image-Staende (alle Images laufen auf :latest)
mkdir "$TMP/_meta"
dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$TMP/_meta/pakete.txt"
apt-mark showmanual > "$TMP/_meta/pakete-manuell.txt"
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' > "$TMP/_meta/docker-container.txt"
docker image ls --digests --format '{{.Repository}}:{{.Tag}}\t{{.Digest}}\t{{.CreatedSince}}' > "$TMP/_meta/docker-images.txt"
ufw status verbose > "$TMP/_meta/ufw-status.txt" 2>&1 || true
# Grafana-Plugins werden nicht gesichert (laedt Grafana selbst nach); nur die Liste, damit nichts unbemerkt fehlt
ls -1 "$VOL/plugins" > "$TMP/_meta/grafana-plugins.txt" 2>/dev/null || true

# Grafana kurz anhalten, damit seine Datenbank in sich stimmig gesichert wird
if [[ "$(docker inspect -f '{{.State.Running}}' "$GRAFANA_CONTAINER" 2>/dev/null)" == true ]]; then
  docker stop "$GRAFANA_CONTAINER" >/dev/null && GRAFANA_STOPPED=1
fi

umask 077
rc=0
tar --zstd -cf "$OUT" \
    --warning=no-file-changed --warning=no-file-ignored \
    --exclude="${VOL#/}/plugins" \
    -C / "${PATHS[@]}" -C "$TMP" _meta || rc=$?

if (( GRAFANA_STOPPED )); then
  docker start "$GRAFANA_CONTAINER" >/dev/null || log "FEHLER: Grafana startet nicht"
  GRAFANA_STOPPED=0
fi

# tar: 1 = Datei hat sich beim Lesen geaendert (unkritisch), >1 = echter Fehler
(( rc <= 1 )) || fail "tar endete mit Code $rc"
tar --zstd -tf "$OUT" >/dev/null || fail "Archiv nicht lesbar"

if [[ "${NO_UPLOAD:-0}" == 1 ]]; then
  log "NO_UPLOAD: Archiv liegt in $OUT ($(du -h "$OUT" | cut -f1))"
  exit 0
fi

# -O: der eingeschraenkte Schluessel erzwingt das alte SCP-Protokoll
scp -O -q -i "$KEY" \
    -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$SSH_DIR/known_hosts" \
    "$OUT" "$TARGET:/mnt/hdd-storage/host-backups/" || fail "Uebertragung nach pve01 fehlgeschlagen"
log "OK: host-$HOST-$TS.tar.zst ($(du -h "$OUT" | cut -f1)) nach pve01 uebertragen"
