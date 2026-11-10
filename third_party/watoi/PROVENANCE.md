# watoi (vendored)

`main.m` is the Core Data importer from **watoi** – *WhatsApp Android To iOS Importer*
by Anton S (residentsummer) and contributors. Licence: GPL-3.0 (see `LICENSE` in this folder).

| | |
|---|---|
| Upstream | https://github.com/residentsummer/watoi (last change 2022-01-03) |
| Base commit | `2b63dd3dc192b763a5a374af0eabf2915803eff0` – *"Bugfix: implemented latest WA schema changes"* by Dennie te Molder (2021-08-21). It lives in watoi's fork network; the `kwvg/watoi` fork that other guides pin to has been deleted, but the commit can still be fetched by SHA from `residentsummer/watoi`. |
| Patch applied | `null-safety.patch` from [MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset](https://github.com/MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset) @ `571f8c7` (GPL-3.0): skips chats / members / senders whose JID is NULL instead of crashing. |
| `applied.diff` | the exact difference between the base commit and the `main.m` shipped here (identical to the patch). |

Why vendored: the importer is a single file, the fork it depends on is gone, and building it with plain
`clang` (no Xcode project, no full Xcode) is equivalent to upstream's project settings
(`CLANG_ENABLE_OBJC_ARC = YES`, links `libsqlite3`). `scripts/00-setup.sh` builds it as:

```
clang -fobjc-arc -O2 -mmacosx-version-min=12.0 -framework Foundation -framework CoreData -lsqlite3 main.m -o build/watoi
```

watoi reads the legacy Android tables `chat_view`, `messages`, `group_participants`; this project feeds it
those tables from `tools/shim_lid.sql`. It writes into `ChatStorage.sqlite` through WhatsApp's own Core Data
model, which this project recovers from the database itself (`tools/extract_model.swift`) instead of
downloading the app.
