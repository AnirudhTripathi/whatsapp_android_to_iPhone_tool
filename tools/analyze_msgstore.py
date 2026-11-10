#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only report on a decrypted Android msgstore.db: health, history size, what will be imported,
how many people have a LID mapping, and which images/documents/stickers still have their file.

usage: analyze_msgstore.py <msgstore.db> <android_root_containing_Media/> [<msgstore_lid.db>]
Prints counts only - never message text, names or numbers.
"""
import datetime as dt
import os
import sqlite3
import sys


def main():
    db, root = sys.argv[1], sys.argv[2]
    shim = sys.argv[3] if len(sys.argv) > 3 else None
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    q = lambda sql, *a: con.execute(sql, a).fetchall()

    print("integrity_check:", q("PRAGMA integrity_check")[0][0])
    tables = {r[0] for r in q("select name from sqlite_master where type in ('table','view')")}
    need = ["message", "chat", "jid", "message_media", "jid_map", "group_participant_user", "message_event"]
    missing = [t for t in need if t not in tables]
    print("modern (2022+) schema:", "yes" if not missing else f"NO - missing {missing} (legacy schema not supported)")
    if missing:
        sys.exit(2)

    ts = lambda ms: dt.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d") if ms else "-"
    n_msg, lo, hi = q("select count(*), min(nullif(timestamp,0)), max(timestamp) from message where _id > 1")[0]
    print(f"\nmessages: {n_msg:,}   first: {ts(lo)}   last: {ts(hi)}")
    chats = dict(q("""select j.server, count(*) from chat c join jid j on j._id=c.jid_row_id
                      where coalesce(c.last_message_row_id,0)>0 group by j.server"""))
    print(f"chats with messages: people={chats.get('s.whatsapp.net', 0) + chats.get('lid', 0):,} "
          f"(phone-keyed {chats.get('s.whatsapp.net', 0):,}, lid-keyed {chats.get('lid', 0):,})  "
          f"groups={chats.get('g.us', 0):,}")
    phone_chats_with_lid = q("""select count(*) from chat c join jid j on j._id=c.jid_row_id
                                where coalesce(c.last_message_row_id,0)>0 and j.server='s.whatsapp.net'
                                  and exists(select 1 from jid_map m where m.jid_row_id=j._id)""")[0][0]
    print(f"phone-keyed chats that have a LID mapping: {phone_chats_with_lid:,} of {chats.get('s.whatsapp.net', 0):,}")

    TYPES = {0: "text", 1: "image", 2: "audio/voice", 3: "video", 4: "contact", 5: "location", 7: "system notice",
             9: "document", 10: "missed call", 13: "gif", 15: "deleted", 20: "sticker", 42: "view-once image",
             43: "view-once video", 66: "poll", 90: "placeholder", 99: "album"}
    print("\nmessage types (top 14):")
    for t, n in q("select message_type, count(*) from message group by 1 order by 2 desc limit 14"):
        print(f"  {TYPES.get(t, 'type ' + str(t)):18s} {n:>9,}")

    print("\nmedia that can become tappable (file still on the phone) vs placeholders:")
    for t, name in [(1, "images"), (9, "documents"), (20, "stickers")]:
        rows = q("""select mm.file_path from message m join message_media mm on mm.message_row_id=m._id
                    where m.message_type=?""", t)
        have = gone = never = 0
        size = 0
        for (path,) in rows:
            if not path:
                never += 1
                continue
            full = os.path.join(root, path)
            if os.path.isfile(full) and os.path.getsize(full) > 0:
                have += 1
                size += os.path.getsize(full)
            else:
                gone += 1
        print(f"  {name:10s} messages={len(rows):>7,}  with file={have:>7,} ({size / 1e9:.2f} GB)"
              f"  file deleted={gone:>6,}  never downloaded={never:>6,}")

    if shim and os.path.exists(shim):
        s = sqlite3.connect(f"file:{shim}?mode=ro", uri=True)
        g = lambda sql: s.execute(sql).fetchone()[0]
        n = {
            "chats": g("select count(*) from chat_view"),
            "groups": g("select count(*) from chat_view where server='g.us'"),
            "lid": g("select count(*) from chat_view where raw_string_jid like '%@lid'"),
            "phone": g("select count(*) from chat_view where raw_string_jid like '%@s.whatsapp.net'"),
            "msgs": g("select count(*) from messages where status<>6"),
            "skipped": g("select count(*) from messages where status=6"),
            "snd_lid": g("select count(*) from messages where remote_resource like '%@lid'"),
            "snd_phone": g("select count(*) from messages where remote_resource like '%@s.whatsapp.net'"),
        }
        print("\nwhat watoi will import (from msgstore_lid.db):")
        print(f"  chats: {n['chats']:,}  (groups {n['groups']:,}, 1:1 by LID {n['lid']:,}, 1:1 by phone {n['phone']:,})")
        print(f"  messages: {n['msgs']:,}  (skipped system/calls/unsupported: {n['skipped']:,})")
        print(f"  group senders by LID: {n['snd_lid']:,}  by phone: {n['snd_phone']:,}")


if __name__ == "__main__":
    main()
