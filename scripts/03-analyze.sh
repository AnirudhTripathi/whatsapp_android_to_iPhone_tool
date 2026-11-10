#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds msgstore_lid.db (the LID-aware input watoi reads) and prints what will be transferred.
# Read-only on msgstore.db. Prints counts only, never message content.
# usage: scripts/03-analyze.sh
source "$(dirname "$0")/lib.sh"
DB="$ANDROID/msgstore.db"; LID="$ANDROID/msgstore_lid.db"
[[ -f "$DB" ]] || die "no $DB - run scripts/02-decrypt.sh first"

say "Building the converter input (msgstore_lid.db)"
rm -f "$LID"; cp "$DB" "$LID"; chmod 600 "$LID"
sqlite3 "$LID" < "$REPO/tools/shim_lid.sql" >/dev/null
sqlite3 "$LID" "drop table if exists sticker_present; create table sticker_present(file_path text primary key);"
if [[ -d "$ANDROID/Media/WhatsApp Stickers" ]]; then
  find "$ANDROID/Media/WhatsApp Stickers" -type f -exec basename {} \; | sort -u \
    | awk '{gsub("\x27","\x27\x27"); print "insert or ignore into sticker_present values(\x27Media/WhatsApp Stickers/" $0 "\x27);"}' \
    | sqlite3 "$LID"
fi
ok "$LID"

say "Report"
"$PY" -I "$REPO/tools/analyze_msgstore.py" "$DB" "$ANDROID" "$LID"
say "Next: set up WhatsApp on the iPhone + calibration media (see README step 4), then scripts/04-backup-iphone.sh"
