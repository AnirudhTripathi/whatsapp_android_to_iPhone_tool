# sticker_inject.py (vendored, unmodified)

From [MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset](https://github.com/MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset)
`scripts/sticker_inject.py` @ `571f8c756e442f5cfdc102467f08acc1f6d787d9`. Licence: GPL-3.0 (see `LICENSE`).

It turns imported `<sticker>` placeholder messages into real sticker messages and adds the `.webp` files to
the iPhone backup. It was proven on a real device by its author (iOS 27.0.1, WhatsApp 26.40.77) and again by
this project (iOS 27.2, WhatsApp 26.44.72).

`tools/media_inject.py` in this project generalises the same mechanism to images and documents, but learns
every convention from native rows on the user's iPhone instead of hard-coding them.

Called by `scripts/06-convert.sh` as:
```
sticker_inject.py <ChatStorage.sqlite> <msgstore_lid.db> <"WhatsApp Stickers" dir> <backup_udid_dir> <baseline_msg_pk> [--dry]
```
