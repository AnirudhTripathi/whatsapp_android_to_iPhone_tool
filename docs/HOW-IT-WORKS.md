# How it works

This document is for developers and for anyone who wants to check what the tool does to their data. The
observed formats themselves are listed in [WHATSAPP-IOS-FORMAT.md](WHATSAPP-IOS-FORMAT.md).

```
 ANDROID (read-only)                     MAC (~/WA-Transfer)                                IPHONE
 ───────────────────                     ───────────────────                                ──────
 E2E backup, 64-digit key ──adb──▶ msgstore.db.crypt15 ──wa-crypt-tools──▶ msgstore.db
 Media/ (Images, Documents,  ─adb─▶ android/Media/                              │ shim_lid.sql
         Stickers…)                                                            ▼
                                                                         msgstore_lid.db (LID-keyed
                                                                         legacy tables for watoi)
 WhatsApp registered + calibration media ◀──────────── idevicebackup2 backup ──────────┐
                                                                                       ▼
                                   backups/<UDID>/  ── ChatStorage.sqlite ─▶ extract_model ─▶ WhatsAppChat.momd
                                        │                    │
                                        │                    ├─ watoi (Core Data import)
                                        │                    ├─ post_lid.sh (native-looking rows)
                                        │                    ├─ sticker_inject.py
                                        │◀── files + Manifest ┴─ media_inject.py (photos, documents)
                                        ▼
                                   verify_backup.py ──▶ idevicebackup2 restore ──────────▶ reboot → WhatsApp
```

## 1. Android: a backup you hold the key to (no root)
WhatsApp's live database is in private app storage, which can't be read without root. The local backup in
`/sdcard/Android/media/com.whatsapp/WhatsApp/Databases/` is readable over `adb`, but it is encrypted:

| file | encrypted with | readable without root? |
|---|---|---|
| `msgstore.db.crypt14` (normal backups) | a key in private storage | no |
| `msgstore.db.crypt15` (end-to-end encrypted backup) | the **64-digit key you were shown** | **yes** |
| `.crypt15` with a password or passkey | a key held in WhatsApp's server HSM | no |

`wa-crypt-tools` (HKDF + AES-256-GCM + zlib) decrypts the `crypt15`. Its 0.2.0 code (pinned) can read the key
from the screenshot of WhatsApp's key screen, and repairs single misread digits by trial-decrypting the start
of the backup. Text-recognition copies of the key often contain Cyrillic look-alikes (`с е а`) and `O` for `0`,
which `02-decrypt.sh` normalises first.

The decrypted database uses the modern (2022+) schema: `chat`, `message`, `message_media`, `jid`, `jid_map`,
`group_participant_user`, `message_event`, … (see `reference/android-msgstore-2.26.43.76-schema.sql`).

## 2. Identities: why everything is keyed by LID
Since 2024 every WhatsApp account has a **LID** (`<number>@lid`) besides its phone JID
(`<phone>@s.whatsapp.net`). Android keeps a mapping in `jid_map(lid_row_id, jid_row_id)`. On the iPhone,
WhatsApp 26.44 stores:

- **1:1 chats** as `ZWACHATSESSION.ZCONTACTJID = <lid>@lid`, with the phone JID in `ZCONTACTIDENTIFIER`,
  and `ZFLAGS = 272`
- **incoming 1:1 messages** with `ZFROMJID = <lid>@lid`
- **group members** that it syncs at registration (thousands of them) as `ZWAGROUPMEMBER.ZMEMBERJID = <lid>@lid`.

Older tools convert everything to phone JIDs. On an iPhone whose WhatsApp is in use, that causes:
- **split chats:** history sits in a phone-keyed chat, and new messages go to WhatsApp's LID-keyed chat
- **duplicate members:** watoi adds phone-keyed members next to the synced LID ones, and the original
  `post.sh` then marks them active.

`tools/shim_lid.sql` resolves every person to a canonical id: the **LID where Android knows it, otherwise
the phone JID**. It also keeps the phone JID alongside (`canon_phone`). In testing, almost every
phone-keyed chat and every LID-keyed chat had a mapping. One person who had an old phone chat and a
newer LID chat on Android ends up as one chat. watoi then finds the iPhone's existing sessions and members by
those ids, so history merges into them. In testing, history merged into the iPhone's existing chats
and group messages linked to already-synced members.

## 3. The data model, recovered from the database itself
watoi writes through Core Data, so it needs WhatsApp's compiled model (`WhatsAppChat.momd`), and it must be
the same version as the store. Other guides download the `.ipa` with `ipatool`, which needs an Apple ID and
often hangs.

Core Data keeps a copy of the model inside every SQLite store, in table `Z_MODELCACHE`, compressed with raw
DEFLATE. `tools/extract_model.swift`:
1. decodes it, and unarchives the `NSManagedObjectModel`
2. checks `isConfiguration(withName:compatibleWithStoreMetadata:)` against the store's own metadata
3. writes a `.momd` (the model plus `VersionInfo.plist`), then reloads it and checks compatibility again.

The model is therefore exactly the one the installed app uses, by construction. `extract_model selftest`
proves the round trip on a synthetic store.

## 4. Import and fix-ups
`watoi` (vendored, built with plain clang) reads the legacy tables `chat_view`, `messages` and
`group_participants`, and inserts `WAChatSession`, `WAGroupInfo`, `WAGroupMember` and `WAMessage` objects.
Core Data fills in the model defaults and the `Z_PRIMARYKEY` bookkeeping. Media messages become text
placeholders (`<image>: caption`) whose `ZSTANZAID` is the Android `key_id`. That's the handle the media step
uses later.

`tools/post_lid.sh` then makes imported rows match what WhatsApp writes itself:
- **session values:** type, flags (256 group / 272 1:1), spotlight status, phone identifier, readable
  fallback name, zero counters
- **message values:** status 8, data-item version 3, `ZSPOTLIGHTSTATUS = -32768`, flags
  16777216 (received) / 16777280 (sent), and sent date = message date
- **last-message pointers:** watoi leaves them NULL (a loop-variable bug), which hides chats, so they're set
- **members watoi had to create**, i.e. people who left groups: kept **inactive**.

It never writes plain text into `ZLASTMESSAGETEXT` (a base64-protobuf column in current builds), and it never
re-activates members.

## 5. Media: photos and documents that open
For every imported placeholder whose file is still in `android/Media`, `tools/media_inject.py`:
1. **links the file into the backup** at `Message/Media/<chat id>/<u0>/<u1>/<uuid>.<ext>` in domain
   `AppDomainGroup-group.net.whatsapp.WhatsApp.shared`, where `u0` and `u1` are the first two characters of a
   lowercase uuid4. The payload goes to `<backup>/<fileID[:2]>/<fileID>`, with
   `fileID = sha1(domain + "-" + relativePath)`. It's a hard link, so no extra disk space is used.
2. **adds `Manifest.db` rows** (flags 1 file / 2 directory). The NSKeyedArchiver `MBFile` blob is **cloned from
   a native WhatsApp media row** and given the new path, size, inode and times. Native media rows have no
   extended attributes and no digest. Every parent directory gets a row.
3. **adds a `ZWAMEDIAITEM`** (photos):
   - `ZFILESIZE`, `ZMEDIALOCALPATH`, `ZMEDIAURLDATE` = message date
   - `ZVCARDNAME` = base64(SHA-256 of the file), `ZVCARDSTRING` = MIME type
   - **`ZLATITUDE` = height, `ZLONGITUDE` = width** (pixels, in display orientation)
   - `ZXMPPTHUMBPATH` → a JPEG `.thumb` at the native size (≈72 px), and `ZTITLE` = caption.
4. **adds a `ZWAMEDIAITEM`** (documents):
   - **`ZAUTHORNAME` = file name**
   - **`ZMOVIEDURATION` = PDF page count**
   - PDFs get a page-1 `.thumb` at ≈96 px (PDFKit)
   - `ZTITLE` = caption only when it is a real caption. Android stores the file name as the "caption" of
     most documents.
5. **turns the message into media:** `ZMESSAGETYPE` 1 (image) or 8 (document), `ZMEDIAITEM`, `ZTEXT = NULL`,
   `ZMEDIASECTIONID` = `YYYY-MM` or `doc-YYYY-MM` (the media gallery), and `ZFLAGS` **copied from the native
   example of the same kind and direction**.
6. **verifies:** message↔item links, every path in `Manifest.db`, payload present and the right size, parent
   directories, `Z_MAX`.

`ZMEDIAURL`, `ZMEDIAKEY` and `ZMETADATA` stay NULL. They describe the copy on WhatsApp's servers, which
expired long ago; the local file is what WhatsApp shows.

**Calibration:** `media_inject.py calibrate` (in `05-calibrate.sh`) reads the native image and document
rows the user created before the backup. It refuses to run without a received **and** sent example of each,
because the flags differ: on WhatsApp 26.44, a received photo is `83886080`, a sent photo `16777280`, a
received PDF `16777216` and a sent PDF `16777600`. Wrong "sent" flags risk WhatsApp treating old media as
unsent.

## 6. Writing back, verifying, restoring
- `ChatStorage.sqlite` goes back into WAL journal mode as a single file, replaces the payload
  `7c/7c7fba66…f01d`, and its `MBFile.Size` is updated. A wrong size makes the restore fail.
- `verify_backup.py` compares the backup with the untouched originals. Every row the conversion added or
  changed must have a payload of exactly the recorded size and listed parent directories. Rows we never
  touched can also show size differences, because iOS records them while live databases are still changing.
  In testing that was well under 1% of files, across many apps. Those are reported, not failed.
- `idevicebackup2 restore --system --settings --skip-apps` restores the same iPhone's backup:
  - `--skip-apps` stops iOS reinstalling or updating any app, so WhatsApp stays on the calibrated version
  - **Find My iPhone must be off** (otherwise `MBErrorDomain 211`, and nothing is changed)
  - the device reboots, which commits the restored app-group data.

## 7. Undo
`06-convert.sh` saves the backup's original `ChatStorage.sqlite` and `Manifest.db` before writing.
`undo.sh` puts them back, and deletes every payload whose `fileID` is not in the original manifest.
Restoring again then returns the iPhone to its state at backup time.

## Known limits
- Only media whose file is on the Android phone can be linked. View-once media stays a placeholder on
  purpose.
- Videos, voice notes and GIFs need their own calibration examples (`ZMOVIEDURATION` = seconds, PTT flags).
  The files are archived by `01-pull-android.sh --all-media`.
- Reactions, quoted replies and edit history are not imported. Polls and events become text.
- macOS only (Core Data and PDFKit). Regular WhatsApp only.
