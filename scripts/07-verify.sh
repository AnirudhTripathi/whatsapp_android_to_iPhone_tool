#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Independent pre-restore check of the modified backup against the untouched originals. Read-only.
# usage: scripts/07-verify.sh
source "$(dirname "$0")/lib.sh"
D="$(backup_udid_dir)"; O="$(latest_originals)"
[[ -n "$O" && -f "$O/Manifest.db" ]] || die "no originals - run scripts/06-convert.sh first"
[[ -f "$RUN/work/ChatStorage.sqlite" ]] || die "no converted database in $RUN/work"
say "Verifying $D against $O"
"$PY" -I "$REPO/tools/verify_backup.py" "$D" "$O" "$RUN/work/ChatStorage.sqlite"
[[ "$(plutil -extract SnapshotState raw "$D/Status.plist" 2>/dev/null)" == "finished" ]] && ok "backup snapshot state: finished" || die "backup snapshot not finished"
say "Next: scripts/08-restore-iphone.sh"
