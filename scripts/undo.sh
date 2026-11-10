#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Puts the backup back exactly as the iPhone wrote it (before 06-convert.sh): restores the saved
# ChatStorage.sqlite + Manifest.db and deletes every file the conversion added. Running
# scripts/08-restore-iphone.sh afterwards returns the iPhone to its pre-conversion state.
# usage: scripts/undo.sh
source "$(dirname "$0")/lib.sh"
D="$(backup_udid_dir)"; O="$(latest_originals)"
[[ -n "$O" && -f "$O/ChatStorage.sqlite" && -f "$O/Manifest.db" ]] || die "no saved originals found in $ORIGINALS"
confirm "Undo the conversion in $D using the originals from $O?" UNDO
"$PY" -I - "$D" "$O/Manifest.db" <<'PY'
import os, sqlite3, sys
u, orig = sys.argv[1], sys.argv[2]
keep = {r[0] for r in sqlite3.connect(f"file:{orig}?immutable=1", uri=True).execute("select fileID from Files")}
removed = 0
for d in os.listdir(u):
    p = os.path.join(u, d)
    if len(d) == 2 and os.path.isdir(p):
        for f in os.listdir(p):
            if len(f) == 40 and f not in keep:
                os.remove(os.path.join(p, f)); removed += 1
print(f"  ✓ removed {removed} files added by the conversion")
PY
cp "$O/ChatStorage.sqlite" "$D/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID"; chmod 644 "$D/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID"
cp "$O/Manifest.db" "$D/Manifest.db"; chmod 644 "$D/Manifest.db"
ok "backup restored to its original state"
