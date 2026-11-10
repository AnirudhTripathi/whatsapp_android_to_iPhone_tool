#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only. Checks the backup holds everything the conversion learns from:
#   * WhatsApp's own data model inside ChatStorage.sqlite (Z_MODELCACHE) - no App Store download needed
#   * native image + document messages in BOTH directions (received and sent) - the "calibration"
# usage: scripts/05-calibrate.sh
source "$(dirname "$0")/lib.sh"
D="$(backup_udid_dir)"; CS="$D/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID"
[[ -f "$CS" ]] || die "no backup - run scripts/04-backup-iphone.sh first"
rm -rf "$CALIB"; mkdir -p "$CALIB"; chmod 700 "$CALIB"
cp "$CS" "$CALIB/ChatStorage.sqlite"; chmod 600 "$CALIB/ChatStorage.sqlite"

say "WhatsApp data model (from the database itself)"
"$BUILD/extract_model" extract "$CALIB/ChatStorage.sqlite" "$CALIB/WhatsAppChat.momd" | tail -3

say "Calibration media"
M="$(zmax "$CALIB/ChatStorage.sqlite" WAMessage)"
REPORT="$("$PY" -I "$REPO/tools/media_inject.py" calibrate "$CALIB/ChatStorage.sqlite" "$D" "$M")"
echo "$REPORT" | grep -v "MBFile template" | sed -E 's/[0-9]{9,}(@lid|@s\.whatsapp\.net|@g\.us)/<id>\1/g'
rm -f "$CALIB"/ChatStorage.sqlite-wal "$CALIB"/ChatStorage.sqlite-shm
if echo "$REPORT" | grep -q "no native example: none"; then
  say "Calibration complete. Next: scripts/06-convert.sh --rehearse   (dry run on copies), then without --rehearse"
else
  echo
  warn "Missing examples. On the iPhone, in any chat: have someone send you 1 photo + 1 PDF (tap to download),"
  warn "and send 1 photo (+ > Photos) + 1 PDF (+ > Document) yourself; wait for the ticks. Then re-run"
  warn "scripts/04-backup-iphone.sh (incremental, ~1 min) and this script."
  exit 1
fi
