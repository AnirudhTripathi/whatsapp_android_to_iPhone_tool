#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copies the end-to-end-encrypted chat backup and the media folders off the Android phone (no root).
# Before running: WhatsApp > Settings > Chats > Chat backup > End-to-end encrypted backup > Turn on >
#   "Use 64-digit encryption key instead" (save the key!) > then tap "Back up" so a fresh .crypt15 is written.
# usage: scripts/01-pull-android.sh [--all-media]
#   default pulls the folders that can be made tappable: Images, Documents, Stickers.
#   --all-media also pulls Video, Voice Notes, Audio, GIFs... (archive only; they stay placeholders).
source "$(dirname "$0")/lib.sh"
need adb

say "Android phone"
adb start-server >/dev/null 2>&1 || true
n="$(adb devices | grep -c -w 'device$' || true)"
if [[ "$n" != "1" ]]; then
  adb devices -l
  die "need exactly one authorised Android device. Enable Developer options > USB debugging, replug, tap Allow."
fi
ok "$(adb shell getprop ro.product.model | tr -d '\r') / Android $(adb shell getprop ro.build.version.release | tr -d '\r')"
adb shell pm list packages | grep -q 'package:com.whatsapp$' || die "WhatsApp (com.whatsapp) not installed. WhatsApp Business is not supported yet."

SRC="$WA_ANDROID_DIR/Databases/msgstore.db.crypt15"
adb shell "ls '$SRC'" >/dev/null 2>&1 || die "No msgstore.db.crypt15. Turn on end-to-end encrypted backup with the 64-digit key, then tap Back up."
ok "backup file: $(adb shell "ls -l '$SRC'" | awk '{print $5" bytes, written "$6" "$7}')"
warn "make sure that date is AFTER you set up the 64-digit key (otherwise tap Back up again)"

say "Pulling the encrypted chat database"
mkdir -p "$ANDROID"; chmod 700 "$ANDROID"
REMOTE="$(adb shell "md5sum '$SRC'" | cut -d' ' -f1)"
adb pull "$SRC" "$ANDROID/msgstore.db.crypt15" | tail -1
[[ "$(md5 -q "$ANDROID/msgstore.db.crypt15")" == "$REMOTE" ]] || die "checksum mismatch - USB problem? try another cable/port or Wireless debugging"
ok "checksum verified"

say "Media folder sizes on the phone"
adb shell "cd '$WA_ANDROID_DIR/Media' && for d in *; do du -sh \"\$d\"; done" 2>/dev/null | sort -k2 | sed 's/^/    /'

FOLDERS=("WhatsApp Images" "WhatsApp Documents" "WhatsApp Stickers")
if [[ "${1:-}" == "--all-media" ]]; then
  FOLDERS+=("WhatsApp Video" "WhatsApp Voice Notes" "WhatsApp Audio" "WhatsApp Animated Gifs" "WhatsApp Video Notes")
fi
say "Pulling media"
mkdir -p "$ANDROID/Media"
for d in "${FOLDERS[@]}"; do
  adb shell "ls -d '$WA_ANDROID_DIR/Media/$d'" >/dev/null 2>&1 || { warn "$d: not on phone"; continue; }
  adb pull "$WA_ANDROID_DIR/Media/$d" "$ANDROID/Media/" | tail -1
  p="$(adb shell "find '$WA_ANDROID_DIR/Media/$d' -type f | wc -l" | tr -d ' \r')"
  m="$(find "$ANDROID/Media/$d" -type f | wc -l | tr -d ' ')"
  [[ "$p" == "$m" ]] && ok "$d: $m files (matches phone)" || die "$d: phone has $p files, Mac has $m - re-run this script"
done
say "Done. Next: scripts/02-decrypt.sh --key-file <file>   (or --screenshot <image>)"
