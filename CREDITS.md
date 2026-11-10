# Credits and third-party code

This project stands on years of reverse-engineering by others. Thank you.

## Code included in this repository

| Component | Author / source | Licence | How it is used |
|---|---|---|---|
| `third_party/watoi/main.m` | [residentsummer/watoi](https://github.com/residentsummer/watoi), schema update by Dennie te Molder (`2b63dd3`) | GPL-3.0 | Core Data importer: writes chats, messages and group members into `ChatStorage.sqlite` through WhatsApp's own data model. See `third_party/watoi/PROVENANCE.md`. |
| `third_party/watoi/null-safety.patch` | [MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset](https://github.com/MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset) | GPL-3.0 | Prevents watoi crashing on NULL JIDs (applied to `main.m`). |
| `third_party/sticker_inject/sticker_inject.py` | MdShahnawazSheikh (same repo, `571f8c7`), unmodified | GPL-3.0 | Turns sticker placeholders into real stickers. |
| `tools/shim_lid.sql` | derived from MdShahnawazSheikh's `shim.sql` | GPL-3.0 | Rewritten to key people by WhatsApp's LID (the way current WhatsApp for iOS does) instead of phone numbers. |
| `tools/post_lid.sh` | derived from MdShahnawazSheikh's `post.sh` | GPL-3.0 | Rewritten for LID chats and for iPhones whose WhatsApp has already synced its groups (no member re-activation, native session flags, phone identifier, safe preview text). |

Everything else (`tools/media_inject.py`, `tools/extract_model.swift`, `tools/pdfthumb.swift`,
`tools/verify_backup.py`, `tools/analyze_msgstore.py`, `scripts/`, `tests/`, `docs/`) is original to this
project, GPL-3.0-or-later.

## Tools used at run time (not included)

| Tool | Licence | Role |
|---|---|---|
| [wa-crypt-tools](https://github.com/ElDavoo/wa-crypt-tools) by ElDavoo, pinned to `b6f6745` | GPL-3.0 | Decrypts `msgstore.db.crypt15` with the 64-digit key; reads the key from a screenshot and repairs misread digits. |
| [libimobiledevice](https://libimobiledevice.org) (`idevicebackup2`, `ideviceinfo`, …) | LGPL-2.1 | Unencrypted iPhone backup and restore over USB. |
| Android platform-tools (`adb`) | Apache-2.0 | Copies the backup and media off the Android phone (no root). |
| [Pillow](https://python-pillow.org) | MIT-CMU | Image dimensions and thumbnails. |
| Tesseract (optional) | Apache-2.0 | OCR for reading the key from a screenshot. |
| Apple Core Data, PDFKit, clang/swiftc (Xcode Command Line Tools) | Apple | Building and running the helpers. |

## Research this project relied on

- **MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset**: the first documented no-reset migration on
  current versions (text + stickers), and the observation that new files can be added to a backup.
- **[n4ze3m's July 2026 write-up](https://n4ze3m.com/blog/recovering-whatsapp-chat-history-android-to-iphone-with-open-source-tools)**:
  proved the watoi route still works and documented the crypt15 / 64-digit-key path.
- **[Jalquin/whatsapp-android-ios-migration-notes](https://github.com/Jalquin/whatsapp-android-ios-migration-notes)**:
  LID identities, media paths (`Message/` + `ZMEDIALOCALPATH`), Manifest/MBFile details, `ZSORT` handling.
- **[Parv3sh/wabridge](https://github.com/Parv3sh/wabridge)** `DESIGN.md`: base64-protobuf columns
  (`ZPUSHNAME`, `ZLASTMESSAGETEXT`) and the open list of reasons media did not open.
- **[mukulkadel/mwatoi](https://github.com/mukulkadel/mwatoi)**, **[KnugiHK/WhatsApp-Chat-Exporter](https://github.com/KnugiHK/WhatsApp-Chat-Exporter)**,
  **MobitrixWATransfer** (non-free licence; read for format confirmation only, no code used) and the forensic
  community's schema notes.

WhatsApp is a trademark of Meta Platforms, Inc.; iPhone and iOS are trademarks of Apple Inc. This project is
not affiliated with, endorsed by or supported by either.
