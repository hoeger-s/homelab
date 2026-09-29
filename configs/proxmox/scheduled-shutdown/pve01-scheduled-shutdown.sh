#!/bin/bash
# Geplantes Herunterfahren von pve01 mit RTC-Weckzeit (Doku: pve01 - Setup-Guide, Zeitschaltung)
set -euo pipefail
WAKE_TIME="08:00"
MAX_WAIT_MIN=60

# Laufendes vzdump-Backup abwarten
for ((i=1; i<=MAX_WAIT_MIN; i++)); do
  pgrep -f 'vzdump' >/dev/null || break
  logger -t pve01-shutdown "vzdump laeuft noch, warte ($i/$MAX_WAIT_MIN min)"
  [[ "${DRY_RUN:-0}" == 1 ]] && break
  sleep 60
done

# Naechstes 08:00 (heute, falls noch nicht vorbei, sonst morgen)
WAKE_EPOCH=$(date -d "today $WAKE_TIME" +%s)
(( WAKE_EPOCH <= $(date +%s) )) && WAKE_EPOCH=$(date -d "tomorrow $WAKE_TIME" +%s)

logger -t pve01-shutdown "Weckzeit: $(date -d @"$WAKE_EPOCH"), fahre herunter"
if [[ "${DRY_RUN:-0}" == 1 ]]; then
  echo "DRY_RUN: Weckzeit waere $(date -d @"$WAKE_EPOCH")"; exit 0
fi
rtcwake -m no -t "$WAKE_EPOCH"
systemctl poweroff
