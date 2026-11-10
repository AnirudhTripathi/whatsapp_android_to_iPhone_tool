#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# The conversion. Saves untouched originals first, then:
#   recover data model -> watoi import (LID-aware input) -> post_lid fix-ups -> stickers ->
#   images & documents -> checks -> write ChatStorage.sqlite back into the backup (+ fix its Manifest size)
#
# usage: scripts/06-convert.sh --rehearse          dry run on COPIES; the backup is not touched (do this first)
#        scripts/06-convert.sh                     real run on the backup (undo: scripts/undo.sh)
# options: --no-stickers  --types image,document  --only-chat <jid>  (pilot one chat)
source "$(dirname "$0")/lib.sh"
REHEARSE=0; STICKERS=1; MEDIA_OPTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rehearse) REHEARSE=1 ;;
    --no-stickers) STICKERS=0 ;;
    --types) MEDIA_OPTS+=(--types "$2"); shift ;;
    --only-chat) MEDIA_OPTS+=(--only-chat "$2"); shift ;;
    *) die "unknown option $1" ;;
  esac; shift
done
LID="$ANDROID/msgstore_lid.db"
[[ -f "$LID" ]] || die "no $LID - run scripts/03-analyze.sh"
[[ -x "$BUILD/watoi" && -x "$BUILD/extract_model" ]] || die "helpers not built - run scripts/00-setup.sh"
SRC="$(backup_udid_dir)"
[[ -f "$SRC/Manifest.db" && -f "$SRC/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID" ]] || die "no complete backup in $SRC"

if [[ $REHEARSE == 1 ]]; then
  say "REHEARSAL - working on copies; the real backup is not modified"
  OUTDIR="$WORK/rehearsal"; rm -rf "$OUTDIR"; mkdir -p "$OUTDIR/backup"
  cp "$SRC/Manifest.db" "$OUTDIR/backup/Manifest.db"
  for d in "$SRC"/??; do ln -s "$d" "$OUTDIR/backup/$(basename "$d")"; done   # read-only use (dry run)
  U="$OUTDIR/backup"; MEDIA_OPTS+=(--dry)
else
  U="$SRC"; OUTDIR="$RUN"
  O="$ORIGINALS/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$O"
  cp -p "$U/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID" "$O/ChatStorage.sqlite"; cp -p "$U/Manifest.db" "$O/Manifest.db"
  chmod 400 "$O"/*
  ok "undo copies saved: $O"
fi
rm -rf "$OUTDIR/work"; mkdir -p "$OUTDIR/work"; W="$OUTDIR/work"
CS="$W/ChatStorage.sqlite"
cp "$SRC/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID" "$CS"; chmod 600 "$CS"
JM="$(sqlite3 "$CS" 'pragma journal_mode;')"

say "1/6 Data model from WhatsApp's own database"
"$BUILD/extract_model" extract "$CS" "$W/WhatsAppChat.momd" | tail -2
rm -f "$CS-wal" "$CS-shm"
S="$(zmax "$CS" WAChatSession)"; M="$(zmax "$CS" WAMessage)"; G="$(zmax "$CS" WAGroupMember)"
ok "baselines: chats=$S messages=$M members=$G journal=$JM"

say "2/6 Importing chats and messages (watoi)"
"$BUILD/watoi" "$LID" "$CS" "$W/WhatsAppChat.momd" > "$W/watoi.log" 2>&1 || { tail -20 "$W/watoi.log"; die "watoi failed (log: $W/watoi.log)"; }
ok "existing iPhone chats matched: $(grep -c ': found' "$W/watoi.log" || true); errors: $(grep -ciE 'exception|abort' "$W/watoi.log" || true)"

say "3/6 Fix-ups (make imported rows look native)"
bash "$REPO/tools/post_lid.sh" "$CS" "$LID" "$S" "$M" "$G"
rm -f "$CS-wal" "$CS-shm"; ok "done"

say "4/6 Stickers"
if [[ $STICKERS == 1 ]]; then
  DRY=(); [[ $REHEARSE == 1 ]] && DRY=(--dry)
  "$PY" -I "$REPO/third_party/sticker_inject/sticker_inject.py" "$CS" "$LID" "$ANDROID/Media/WhatsApp Stickers" "$U" "$M" ${DRY[@]+"${DRY[@]}"}
else ok "skipped"; fi

say "5/6 Images and documents"
"$PY" -I "$REPO/tools/media_inject.py" inject "$CS" "$LID" "$ANDROID" "$U" "$M" "$W" ${MEDIA_OPTS[@]+"${MEDIA_OPTS[@]}"}

say "6/6 Checks"
sqlite3 "$CS" "
select '  integrity: '||(select integrity_check from pragma_integrity_check);
select '  chats: '||count(*) from ZWACHATSESSION;
select '  messages: '||count(*) from ZWAMESSAGE;
select '  images: '||count(*) from ZWAMESSAGE where ZMESSAGETYPE=1;
select '  documents: '||count(*) from ZWAMESSAGE where ZMESSAGETYPE=8;
select '  stickers: '||count(*) from ZWAMESSAGE where ZMESSAGETYPE=15;
select '  duplicate chat keys (must be 0): '||count(*) from (select ZCONTACTJID from ZWACHATSESSION group by 1 having count(*)>1);
select '  chats without last message (must be 0): '||count(*) from ZWACHATSESSION s where s.ZLASTMESSAGE is null and exists(select 1 from ZWAMESSAGE m where m.ZCHATSESSION=s.Z_PK);
select '  active members added (must be 0): '||count(*) from ZWAGROUPMEMBER where Z_PK>$G and ZISACTIVE=1;"

if [[ $REHEARSE == 1 ]]; then
  say "Rehearsal finished. Nothing was written to the backup. If the numbers look right: scripts/06-convert.sh"
  exit 0
fi

say "Writing the converted database into the backup"
sqlite3 "$CS" "pragma journal_mode=$JM;" >/dev/null; rm -f "$CS-wal" "$CS-shm"
cp "$CS" "$U/${CHATSTORAGE_ID:0:2}/$CHATSTORAGE_ID"
"$PY" -I - "$U/Manifest.db" "$CHATSTORAGE_ID" "$(stat -f%z "$CS")" <<'PY'
import plistlib, sqlite3, sys
db, fid, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
c = sqlite3.connect(db)
d = plistlib.loads(c.execute("select file from Files where fileID=?", (fid,)).fetchone()[0])
d["$objects"][d["$top"]["root"].data]["Size"] = size
c.execute("update Files set file=? where fileID=?", (plistlib.dumps(d, fmt=plistlib.FMT_BINARY), fid)); c.commit()
print(f"  ✓ Manifest.db: ChatStorage.sqlite size = {size}")
PY
say "Conversion done. Next: scripts/07-verify.sh"
