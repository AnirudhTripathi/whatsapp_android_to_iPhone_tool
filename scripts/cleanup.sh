#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Deletes everything sensitive from $WA_WORK once you are happy with the result:
# the unencrypted iPhone backup, decrypted chat databases, undo copies, working files and logs.
# Keeps android/Media (your media archive) unless --all.
# usage: scripts/cleanup.sh [--all]
source "$(dirname "$0")/lib.sh"
ALL=0; [[ "${1:-}" == "--all" ]] && ALL=1
echo "Will delete from $WORK:"
for p in backups originals run rehearsal calibration android/msgstore.db android/msgstore.db.crypt15 \
         android/msgstore_lid.db backup.log restore.log; do
  [[ -e "$WORK/$p" ]] && printf '  %-34s %s\n' "$p" "$(du -sh "$WORK/$p" | cut -f1)"
done
[[ $ALL == 1 && -d "$ANDROID/Media" ]] && printf '  %-34s %s\n' "android/Media" "$(du -sh "$ANDROID/Media" | cut -f1)"
[[ $ALL == 0 ]] && echo "Keeping android/Media (your media archive) - pass --all to delete it too."
confirm "This cannot be undone." DELETE
chmod -R u+w "$ORIGINALS" 2>/dev/null || true
rm -rf "$BACKUPS" "$ORIGINALS" "$RUN" "$WORK/rehearsal" "$CALIB" "$WORK/backup.log" "$WORK/restore.log" \
       "$ANDROID/msgstore.db" "$ANDROID/msgstore.db.crypt15" "$ANDROID/msgstore_lid.db" "$ANDROID"/*.db-*
[[ $ALL == 1 ]] && rm -rf "$WORK"
ok "deleted. Also delete any key file / key screenshot you created, and empty the Trash."
