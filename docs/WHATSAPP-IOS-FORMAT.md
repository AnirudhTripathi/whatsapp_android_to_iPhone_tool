# WhatsApp for iOS: observed formats

Observed on **WhatsApp 26.44.72, iOS 27.2, November 2026**, from rows WhatsApp wrote itself
(calibration). Column lists for all relevant tables: `reference/ios-chatstorage-26.44.72-schema.sql`.
**Never hard-code these.** The tools learn them per device. They are listed here to help maintainers spot
changes.

## Files
| | |
|---|---|
| App-group domain | `AppDomainGroup-group.net.whatsapp.WhatsApp.shared` |
| Chat database | `ChatStorage.sqlite`, fileID `7c7fba66680ef796b916b067077cc246adacf01d` (same on every device), WAL mode, no `-wal` in backups |
| Other databases | `LID.sqlite` (`ZWAZACCOUNT`: LID ↔ phone), `ContactsV2.sqlite`, `Sticker.sqlite`, `CallHistory.sqlite`, … (not modified) |
| Media path in DB | `ZWAMEDIAITEM.ZMEDIALOCALPATH = Media/<chat id>/<u0>/<u1>/<uuid>.<ext>` |
| Media path in backup | `Message/` + `ZMEDIALOCALPATH` |
| Thumbnail | same folder, `<uuid>.thumb`, JPEG. Photo ≈72 px longest side, PDF page 1 ≈96 px |
| MBFile, file | `Mode 0100644`, `ProtectionClass 3`, `UserID/GroupID 501`, `Flags 0`, no `ExtendedAttributes`, no `Digest` |
| MBFile, directory | `Mode 040775` or `040755` (both seen), `ProtectionClass 0`, `Size 0` |

## Core Data entities
`Z_PRIMARYKEY` lists 15 entities. The ones the tools touch: `WAChatSession`, `WAMessage`, `WAMediaItem`,
`WAGroupMember`, `WAGroupInfo`. `Z_ENT` values are looked up by name, never assumed. `Z_MODELCACHE` holds the
compiled model (raw DEFLATE).

## Chat sessions (`ZWACHATSESSION`)
| | 1:1 | group |
|---|---|---|
| `ZCONTACTJID` | `<lid>@lid` | `<id>@g.us` |
| `ZCONTACTIDENTIFIER` | `<phone>@s.whatsapp.net` | NULL |
| `ZSESSIONTYPE` | 0 | 1 (4 = community) |
| `ZFLAGS` | 272 | 256 (other values seen: 524544, 268435712) |
| `ZSPOTLIGHTSTATUS` | -5 | 1 |
| `ZLASTMESSAGETEXT` | base64 protobuf. **Never write plain text here.** | |

## Messages (`ZWAMESSAGE`)
| kind | `ZMESSAGETYPE` | received `ZFLAGS` | sent `ZFLAGS` | `ZMEDIASECTIONID` |
|---|---|---|---|---|
| text | 0 | 16777216 | 16777280 | NULL |
| image | 1 | 83886080 | 16777280 | `YYYY-MM` |
| document | 8 | 16777216 (PDF) / 83886080 (a JPEG sent as a document) | 16777600 (PDF) | `doc-YYYY-MM` |
| sticker | 15 | 83886080 | 16781376 (seen on 26.40.77) | |
| system / group event | 6 | | | |

Other values:
- `ZMESSAGESTATUS` is 8 (read) for old messages; a just-sent message shows 6.
- `ZDATAITEMVERSION` 3, `ZSPOTLIGHTSTATUS` -32768.
- Received messages in 1:1 chats have `ZFROMJID = <lid>@lid`; sent ones have `ZTOJID = <lid>@lid`.
- Dates are Cocoa seconds (Unix − 978307200).
- `ZPUSHNAME` is base64 protobuf.
- Native text messages also carry a `ZMEDIAITEM` (metadata). Imported text works without it.

## Media items (`ZWAMEDIAITEM`)
| column | photo | document |
|---|---|---|
| `ZFILESIZE` | bytes | bytes |
| `ZVCARDNAME` | base64(SHA-256(file)) | base64(SHA-256(file)) |
| `ZVCARDSTRING` | MIME (`image/jpeg`) | MIME (`application/pdf`, …) |
| `ZLATITUDE` / `ZLONGITUDE` | **height / width** in pixels | 0 / 0 |
| `ZMOVIEDURATION` | 0 | **page count** (PDF) |
| `ZAUTHORNAME` | — | **file name** |
| `ZTITLE` | caption | (caption) |
| `ZXMPPTHUMBPATH` | `<uuid>.thumb` | `<uuid>.thumb` for PDFs |
| `ZMEDIAURLDATE` | message date | message date |
| `ZMEDIAORIGIN` | 0 | 0 |
| `ZMEDIAURL`, `ZMEDIAKEY`, `ZMETADATA` | server copy (left NULL on import) | same |

## Group members (`ZWAGROUPMEMBER`)
WhatsApp syncs current members at registration:
- `ZMEMBERJID = <lid>@lid`, `ZISACTIVE = 1`
- `ZCONTACTNAME` and `ZCONTACTIDENTIFIER` are NULL; names come from `LID.sqlite` and the address book
- one inactive `@s.whatsapp.net` row per group for the account owner.
