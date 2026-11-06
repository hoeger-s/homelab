#!/bin/bash
# Taegliche Sicherung der Host-Konfiguration von pve01 (Backup-Konzept Stufe 2)
# Archiv: /mnt/hdd-storage/host-backups/host-pve01-JJJJ_MM_TT-HH_MM_SS.tar.zst
# Danach Aufbewahrung 7/4/3 fuer ALLE Host-Archive (pve01 und mon01; mon01 darf nur schreiben).
# Test ohne Wirkung: DRY_RUN=1 /usr/local/sbin/pve01-host-backup.sh
set -euo pipefail
shopt -s nullglob

HOST="pve01"
MOUNT="${MOUNT:-/mnt/hdd-storage}"
DEST="${DEST:-$MOUNT/host-backups}"
PRUNE_HOSTS=(pve01 mon01)
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=3

# Was gesichert wird (relativ zu /). /etc enthaelt /etc/pve (pmxcfs), darum kein --one-file-system.
cd /
PATHS=()
for p in etc usr/local/sbin root/.ssh home/*/.ssh; do [[ -e $p ]] && PATHS+=("$p"); done

log() { logger -t host-backup "$*"; echo "$*"; }
fail() { log "FEHLER: $*"; exit 1; }

# Nie auf die Systemplatte schreiben, falls die HDD fehlt
mountpoint -q "$MOUNT" || fail "$MOUNT ist nicht eingehaengt"
[[ -d "$DEST" ]] || fail "$DEST fehlt"

# --- Sicherung ---------------------------------------------------------------
if [[ "${DRY_RUN:-0}" == 1 ]]; then
  log "DRY_RUN: keine Sicherung, nur Anzeige der Aufbewahrung"
else
  TS=$(date +%Y_%m_%d-%H_%M_%S)
  OUT="$DEST/host-$HOST-$TS.tar.zst"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP" "$OUT.partial"' EXIT

  # Paketliste fuer die Neuinstallation
  mkdir "$TMP/_meta"
  dpkg-query -W -f='${binary:Package}\t${Version}\n' > "$TMP/_meta/pakete.txt"
  apt-mark showmanual > "$TMP/_meta/pakete-manuell.txt"
  if command -v pveversion >/dev/null; then pveversion -v > "$TMP/_meta/pveversion.txt"; fi

  umask 077
  rc=0
  tar --zstd -cf "$OUT.partial" \
      --warning=no-file-changed --warning=no-file-ignored \
      -C / "${PATHS[@]}" -C "$TMP" _meta || rc=$?
  # tar: 1 = Datei hat sich beim Lesen geaendert (unkritisch), >1 = echter Fehler
  (( rc <= 1 )) || fail "tar endete mit Code $rc"

  tar --zstd -tf "$OUT.partial" >/dev/null || fail "Archiv nicht lesbar"
  mv "$OUT.partial" "$OUT"
  log "OK: $OUT ($(du -h "$OUT" | cut -f1))"
fi

# --- Aufbewahrung ------------------------------------------------------------
# Wie Proxmox: je Tag/Woche/Monat bleibt der neueste Stand. Behalten wird, was
# mindestens eine Regel braucht. Der neueste Stand bleibt also immer.
prune() {
  local host=$1 f name stamp day week month keep
  local -A seen_d=() seen_w=() seen_m=()
  local nd=0 nw=0 nm=0
  local files=("$DEST"/host-"$host"-*.tar.zst)
  (( ${#files[@]} )) || return 0

  while IFS= read -r f; do
    name=${f##*/}
    stamp=${name#host-"$host"-}
    stamp=${stamp%.tar.zst}
    # Nur Dateien im erwarteten Format anfassen
    [[ $stamp =~ ^[0-9]{4}_[0-9]{2}_[0-9]{2}-[0-9]{2}_[0-9]{2}_[0-9]{2}$ ]] || continue
    day=${stamp:0:10}
    week=$(date -d "${day//_/-}" +%G-%V)
    month=${day:0:7}
    keep=0
    if [[ -z ${seen_d[$day]:-} ]] && (( nd < KEEP_DAILY )); then seen_d[$day]=1; nd=$((nd+1)); keep=1; fi
    if [[ -z ${seen_w[$week]:-} ]] && (( nw < KEEP_WEEKLY )); then seen_w[$week]=1; nw=$((nw+1)); keep=1; fi
    if [[ -z ${seen_m[$month]:-} ]] && (( nm < KEEP_MONTHLY )); then seen_m[$month]=1; nm=$((nm+1)); keep=1; fi
    if (( keep )); then
      continue
    elif [[ "${DRY_RUN:-0}" == 1 ]]; then
      log "DRY_RUN: wuerde loeschen: $name"
    else
      rm -f -- "$f" && log "Aufbewahrung: geloescht $name"
    fi
  done < <(printf '%s\n' "${files[@]}" | sort -r)
}

for h in "${PRUNE_HOSTS[@]}"; do prune "$h"; done
