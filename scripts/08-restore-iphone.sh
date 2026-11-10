#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Restores the converted backup to the SAME iPhone it was taken from. Not a factory reset: everything comes
# back as it was at backup time, plus the imported WhatsApp history. Takes ~20-40 min for ~40 GB.
# usage: scripts/08-restore-iphone.sh
source "$(dirname "$0")/lib.sh"
need idevicebackup2
U="$(udid)"; D="$(backup_udid_dir)"
[[ "$(basename "$D")" == "$U" ]] || die "the connected iPhone ($U) is not the one this backup came from ($(basename "$D"))"
idevicepair -u "$U" validate >/dev/null || die "iPhone not trusted/unlocked"

cat <<'TXT'

Before restoring, on the iPhone:
  1. Find My iPhone is OFF   (Settings > your name > Find My). The restore is refused otherwise (error 211).
  2. Airplane Mode ON and Wi-Fi OFF - new WhatsApp messages then wait on WhatsApp's servers and arrive
     after the restore instead of being lost.
  3. Unlocked, plugged in, and you will not unplug it until the lock screen appears after the reboot.
Anything changed on the iPhone since the last backup (photos, messages...) will be lost.
TXT
confirm "Restore the converted backup to this iPhone now?" RESTORE

say "Restoring (the iPhone shows 'Restore in Progress' and reboots at the end)"
idevicebackup2 -u "$U" restore --system --settings --skip-apps "$BACKUPS" 2>&1 | tee "$WORK/restore.log" \
  | grep -E --line-buffered "Restore Successful|ERROR|rror|211|SpringBoard" || true
if grep -q "Restore Successful" "$WORK/restore.log"; then
  cat <<'TXT'

Restore Successful. After the iPhone reboots:
  1. Unlock it, finish any setup screens (iCloud may ask for your Apple ID password).
  2. Airplane Mode OFF, Wi-Fi on. Queued messages arrive.
  3. Open WhatsApp. If it asks to verify your number, do it. If it offers "Restore chat history" from
     iCloud, tap SKIP - that would replace the imported history.
  4. Check old chats, groups, tap old photos and PDFs, and have someone message you (it should land in the
     same chat as their history).
  5. Turn Find My iPhone back on. When happy: scripts/cleanup.sh
TXT
else
  grep -q "211" "$WORK/restore.log" && warn "Find My iPhone is still on: turn it off and run this again (nothing was changed)."
  grep -q "SpringBoard" "$WORK/restore.log" && warn "Force-restart the iPhone (vol up, vol down, hold side), unlock, run again."
  die "restore did not complete - see $WORK/restore.log"
fi
