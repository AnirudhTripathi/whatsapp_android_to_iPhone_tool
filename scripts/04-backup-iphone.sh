#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Unencrypted local backup of the iPhone into $WORK/backups. First run = full backup; later runs are
# incremental (only changes, ~1 minute) into the same folder.
# Before: WhatsApp registered on the iPhone with the SAME number, calibration media sent AND received,
#         Finder > iPhone > "Encrypt local backup" UNticked, iPhone unlocked + trusted + plugged in.
# usage: scripts/04-backup-iphone.sh
source "$(dirname "$0")/lib.sh"
need idevicebackup2; need ideviceinfo; need idevicepair
U="$(udid)"
idevicepair -u "$U" validate >/dev/null || die "iPhone not trusted: unlock it, tap Trust, enter passcode"
ok "iPhone $(ideviceinfo -u "$U" -k ProductType) / iOS $(ideviceinfo -u "$U" -k ProductVersion)"

ENC="$(ideviceinfo -u "$U" -q com.apple.mobile.backup -k WillEncrypt 2>/dev/null || true)"
[[ "$ENC" == "true" ]] && die "Backup encryption is ON. Finder > your iPhone > untick 'Encrypt local backup' (needs the backup password), then re-run."
ok "local backup encryption is off"

if command -v ideviceinstaller >/dev/null; then
  V="$(ideviceinstaller -u "$U" list --user 2>/dev/null | grep '^net.whatsapp.WhatsApp,' | cut -d'"' -f2 || true)"
  [[ -n "$V" ]] && ok "WhatsApp $V installed" || die "WhatsApp is not installed on the iPhone"
fi

USED_GB="$(ideviceinfo -u "$U" -q com.apple.disk_usage 2>/dev/null | awk -F': ' '/TotalDataCapacity/{c=$2}/TotalDataAvailable/{a=$2}END{printf "%.0f",(c-a)/1e9}')"
FREE_GB="$(df -g "$WORK" | awk 'NR==2{print $4}')"
ok "iPhone data ~${USED_GB} GB, free on this Mac ${FREE_GB} GB"
(( ${FREE_GB:-0} > ${USED_GB:-0} + 15 )) || warn "free space looks tight (need roughly iPhone data + media + 15 GB)"

mkdir -p "$BACKUPS"; chmod 700 "$BACKUPS"
MODE=""; LABEL="incremental"
[[ -f "$BACKUPS/$U/Manifest.db" ]] || { MODE="--full"; LABEL="full"; }
say "Backing up ($LABEL) - keep the iPhone unlocked and plugged in"
START=$(date +%s)
idevicebackup2 -u "$U" backup $MODE "$BACKUPS" 2>&1 | tee "$WORK/backup.log" | grep -E --line-buffered "Received|Backup Successful|ERROR|rror" || true
grep -q "Backup Successful" "$WORK/backup.log" || die "backup did not finish - see $WORK/backup.log"
ok "done in $(( ($(date +%s)-START)/60 )) min, $(du -sh "$BACKUPS/$U" | cut -f1)"

D="$BACKUPS/$U"
[[ "$(plutil -extract IsEncrypted raw "$D/Manifest.plist" 2>/dev/null)" == "false" ]] || die "backup is encrypted - turn encryption off and back up again"
[[ -f "$D/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID" ]] || die "WhatsApp's ChatStorage.sqlite is not in the backup - is WhatsApp registered on the iPhone?"
ok "WhatsApp data present ($(sqlite3 "file:$D/Manifest.db?immutable=1" "select count(*) from Files where domain='$DOMAIN'") entries)"
say "Next: scripts/05-calibrate.sh"
