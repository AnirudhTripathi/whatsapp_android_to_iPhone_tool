#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Decrypts msgstore.db.crypt15 with your 64-digit key. The key is never taken on the command line
# (it would end up in shell history) - give a file containing it, or the screenshot of the key screen.
#
# usage: scripts/02-decrypt.sh --key-file  key.txt         (64 hex digits; spaces/newlines are fine)
#        scripts/02-decrypt.sh --screenshot key.png        (original screenshot of WhatsApp's key screen)
#
# Key copied with phone/Mac text recognition (Live Text, Lens...)? It often contains look-alike letters
# (Cyrillic с/е/а, letter O for zero). This script normalises those; wa-crypt-tools then also repairs a
# single misread digit, swapped digits/groups and a grid read column-wise, verifying each guess against
# the backup itself. If it still fails, use --screenshot.
source "$(dirname "$0")/lib.sh"
WADECRYPT="$VENV/bin/wadecrypt"; [[ -x "$WADECRYPT" ]] || die "run scripts/00-setup.sh first"
IN="$ANDROID/msgstore.db.crypt15"; OUT="$ANDROID/msgstore.db"
[[ -f "$IN" ]] || die "no $IN - run scripts/01-pull-android.sh first"
[[ $# -eq 2 ]] || die "usage: $0 --key-file <file> | --screenshot <image>"
rm -f "$OUT"

say "Decrypting"
case "$1" in
  --key-file)
    KEY="$("$PY" -I - "$2" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
look_alike = {"с": "c", "е": "e", "а": "a", "С": "C", "Е": "E", "А": "A",
              "O": "0", "o": "0", "О": "0", "о": "0", "l": "1", "I": "1"}
d = re.sub(r"\s", "", "".join(look_alike.get(c, c) for c in s))
if not re.fullmatch(r"[0-9a-fA-F]{64}", d):
    sys.exit(f"key file must contain 64 hex digits (found {len(re.sub('[^0-9a-fA-F]', '', d))} after cleanup)")
print(d.lower())
PY
)" || die "could not read a 64-digit key from $2"
    OUTPUT="$("$WADECRYPT" "$KEY" "$IN" "$OUT" 2>&1 || true)"; echo "${OUTPUT//$KEY/<key>}" | tail -4; unset KEY ;;
  --screenshot)
    "$WADECRYPT" "$2" "$IN" "$OUT" 2>&1 | sed -E 's/[0-9a-fA-F]{16,}/<key>/g' | tail -4 ;;
  *) die "usage: $0 --key-file <file> | --screenshot <image>" ;;
esac

[[ -f "$OUT" ]] && [[ "$(head -c 15 "$OUT")" == "SQLite format 3" ]] || {
  rm -f "$OUT"; die "decryption failed: the key does not match this backup. Re-check the key, try --screenshot, or set up a new key and back up again."; }
chmod 600 "$OUT"
ok "decrypted: $OUT ($(du -h "$OUT" | cut -f1))"
say "Next: scripts/03-analyze.sh"
