# wa-android-to-iphone

**Move your WhatsApp history from Android to an iPhone that is already set up, including photos and
documents you can tap open, with free, open-source tools. No factory reset, no root, no jailbreak, no paid
app, no App Store login.**

Apple's *Move to iOS* is the only official route. It requires erasing the iPhone, and it often fails
part-way. This project does what the paid "WhatsApp transfer" apps do, in the open, on your own Mac:

1. decrypt the Android chat backup with your 64-digit key
2. convert it into WhatsApp-for-iOS's own database format
3. place it, with your photos and documents, inside a backup of your iPhone
4. restore that backup.

> **Status: working on a real device (November 2026).** Tested from Android 13 (WhatsApp 2.26.43.76) to
> iOS 27.2 (WhatsApp 26.44.72) with a large chat history: 1:1 chats and groups, **photos and documents
> that open when tapped**, and stickers. WhatsApp opened with the full history without asking to
> re-verify the number, and everything checked worked.
> WhatsApp changes its formats often, so read [Safety](#safety-and-privacy) and keep the undo path.

---

## What transfers

| | |
|---|---|
| ✅ Text messages, 1:1 and group, with dates, direction, sender and starred flag | merged into chats that already exist on the iPhone, in date order |
| ✅ **Photos**: tap to open, with thumbnail and correct size | if the file is still on the Android phone |
| ✅ **Documents** (PDF, Word, Excel, …): tap to open, PDF preview and page count | if the file is still on the Android phone |
| ✅ Stickers | if the `.webp` is still on the phone |
| ✅ Captions, polls and events (as text), deleted-message markers, contact cards, locations | |
| ➖ Photos and documents whose file is gone from the phone | placeholder with caption (`<image>`, `<document>: name`) |
| ➖ Videos, voice notes, audio, GIFs | placeholders; the files are archived on your Mac (see the [Roadmap](#roadmap)) |
| ❌ Call history, "X joined" system notices, reactions, view-once media, channels, status updates, WhatsApp Business | |

Expect some media to stay as placeholders. Android only keeps files WhatsApp actually downloaded, and that
you haven't deleted. `scripts/03-analyze.sh` shows the exact numbers before anything happens.

## Why this works when other tools don't

This project builds on existing work (see [CREDITS.md](CREDITS.md)) and adds what was missing:

- **Media that opens.** No public open-source tool had working photos or documents on a real iPhone.
  `tools/media_inject.py` learns the exact database and backup conventions from a photo and a PDF you send
  and receive on the iPhone ("calibration"), instead of guessing them.
- **Works on an iPhone where WhatsApp is already in use.** Current WhatsApp for iOS identifies people by
  **LID** (`<number>@lid`), not by phone number, and syncs your groups and members at registration. This
  project keys imported chats and group senders the same way. Without that, every chat splits in two the
  first time the contact writes, and group member lists show everyone twice.
- **No App Store download, Apple ID or Xcode.** Other guides need the WhatsApp `.ipa` (via `ipatool`,
  which often hangs) to get its data model. This project recovers the model from the cache Core Data keeps
  inside WhatsApp's own database, then verifies it. Only the free Xcode Command Line Tools are needed.
- **Safety rails.** A dry-run rehearsal on copies, an independent pre-restore verifier, a one-command
  undo, and a confirmation word before anything touches the phone.

Details: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) · formats: [docs/WHATSAPP-IOS-FORMAT.md](docs/WHATSAPP-IOS-FORMAT.md)

---

## Requirements

- **A Mac** (Apple Silicon or Intel, macOS 12+) with **Homebrew** and the **Xcode Command Line Tools**
  (`xcode-select --install`). Full Xcode is *not* needed.
- **Python 3.11 or newer.** The `python3` that comes with the Command Line Tools is 3.9, so setup installs a
  newer one with Homebrew if needed.
- **An internet connection** for setup. After that, everything runs offline.
- **Free disk space** of about your iPhone's used data + your WhatsApp media + 15 GB. Set
  `export WA_WORK=/Volumes/YourSSD/WA-Transfer` to work on an external drive.
- **USB cables** for both phones.
- **The Android phone** with your WhatsApp account still logged in (regular WhatsApp, not Business).
- **The iPhone**, already set up, with WhatsApp installed from the App Store.
- About **2 hours**, mostly waiting on copies. Your Android phone is only read from, never changed.

## Setup

Do this once on the Mac. It doesn't touch either phone.

```bash
xcode-select --install       # Xcode Command Line Tools (skip if already installed)
                             # Homebrew: see https://brew.sh (skip if already installed)
git clone https://github.com/AnirudhTripathi/whatsapp_android_to_iPhone_tool.git
cd whatsapp_android_to_iPhone_tool
scripts/00-setup.sh          # add --no-ocr if you won't read the key from a screenshot
```

`scripts/00-setup.sh` can be re-run safely. It:

1. installs the command-line tools with Homebrew: `libimobiledevice`, `ideviceinstaller`, Android
   platform-tools (`adb`), and Tesseract for reading the key from a screenshot (skipped with `--no-ocr`)
2. makes sure Python is 3.11 or newer, installing it with Homebrew if needed
3. creates a Python environment in `.venv` and installs the packages in [`requirements.txt`](requirements.txt):
   - **wa-crypt-tools**, pinned to an exact commit, to decrypt the Android backup
   - **Pillow**, for image sizes and thumbnails
4. compiles the three helpers into `build/`: `watoi`, `extract_model` and `pdfthumb`
5. runs the offline test suite, which uses synthetic data only.

When it prints **Setup complete**, continue with [step 1](#1-android-make-a-backup-you-can-decrypt).

To install only the Python packages by hand, run the following. The scripts always use `.venv/bin/python`,
so keep the environment at `.venv`.

```bash
python3 -m venv .venv                     # python3 --version must be 3.11 or newer
.venv/bin/pip install -r requirements.txt
```

## Safety and privacy

- **Everything runs on your Mac.** No data is uploaded anywhere; there is no telemetry.
- Your data lives in `~/WA-Transfer` (or `$WA_WORK`), **outside this repository**. That folder will contain
  your decrypted chats and an unencrypted iPhone backup. Run `scripts/cleanup.sh` when you are done.
- The 64-digit key is never typed on the command line and never printed.
- The restore puts back **your own iPhone's backup**, taken minutes earlier, plus the imported WhatsApp
  history. It is not a factory reset, but anything that changes on the iPhone between the backup and the
  restore is lost. Use Airplane Mode (step 8) so no WhatsApp message is lost.
- An unencrypted backup does not carry Keychain and Health data. On the same iPhone they stay as they are,
  and iCloud Keychain and Health sync bring them back anyway. Check those are on.
- This is unsupported by WhatsApp and Apple. Keep your Android phone untouched until you are happy.

---

## Step by step

### 0. Setup on the Mac (once)
Follow [Setup](#setup) above: clone the repository and run `scripts/00-setup.sh`.

### 1. Android: make a backup you can decrypt
1. In WhatsApp, go to **Settings → Chats → Chat backup → End-to-end encrypted backup → Turn on**.
2. Choose **Use 64-digit encryption key instead**. Do not use a password or passkey; those can't be
   decrypted offline.
3. **Save the key.** Take a screenshot of the key screen, or write it down. WhatsApp shows it once.
4. Back on *Chat backup*, tap **Back up** and wait for it to finish. This writes the `msgstore.db.crypt15`
   file the tools read.
5. Turn on USB debugging: **Settings → About phone** (Samsung: **→ Software information**) → tap **Build
   number** 7 times. Then **Settings → Developer options → USB debugging: on**. Plug in, then tap **Allow**
   and *Always allow from this computer*.

### 2. Copy WhatsApp off the Android phone
```bash
scripts/01-pull-android.sh               # chat backup + Images, Documents, Stickers (counts verified)
scripts/01-pull-android.sh --all-media   # optional: also archives videos, voice notes, audio, GIFs
```

### 3. Decrypt and see what will transfer
Put the key in a text file, or use the screenshot:
```bash
pbpaste > ~/key.txt && chmod 600 ~/key.txt        # after copying the 64 digits
scripts/02-decrypt.sh --key-file ~/key.txt         # or:  --screenshot ~/key.png
scripts/03-analyze.sh                              # counts only: chats, messages, media with/without file
```
If you copied the key with Live Text or Google Lens, it may contain look-alike letters. The script fixes
those, and wa-crypt-tools repairs a single misread digit. If decryption still fails, use `--screenshot` with
the original screenshot.

### 4. iPhone: register WhatsApp and calibrate
1. **Settings → App Store → App Updates: off**, so WhatsApp's version can't change mid-way.
2. Open **WhatsApp** and register your **same phone number**. **Skip** any offer to restore from iCloud or
   transfer from Android. This logs the Android phone out; its data was already copied in step 2.
3. **Calibration** (2 minutes), in any chat:
   - have someone send you **1 photo and 1 PDF**, then tap both so they download
   - **send 1 photo** (**+ → Photos & Videos**, not as a document) and **1 PDF** (**+ → Document**)
   - wait until all of them show ticks ✓✓.
4. **Finder** → select your iPhone → untick **Encrypt local backup** (it asks for the backup password).

### 5. Back up the iPhone and check the calibration
```bash
scripts/04-backup-iphone.sh     # full unencrypted backup (≈10-20 min); re-runs are incremental (≈1 min)
scripts/05-calibrate.sh         # read-only: recovers WhatsApp's data model, finds your calibration media
```
If `05-calibrate.sh` reports a missing example, do the missing send or receive, then re-run both scripts.
From here until step 8, **don't use WhatsApp on the iPhone**.

### 6. Rehearse, then convert
```bash
scripts/06-convert.sh --rehearse   # dry run on COPIES - read the numbers
scripts/06-convert.sh              # real run on the backup (saves undo copies first)
```
Options: `--no-stickers`, `--types image` or `--types document`, and `--only-chat <jid>` to pilot one chat.

### 7. Verify
```bash
scripts/07-verify.sh    # independent check against the untouched originals; must say "safe to restore"
```

### 8. Restore
On the iPhone, in this order:
1. **Settings → [your name] → Find My → Find My iPhone: off.** This needs internet and your Apple ID
   password, so do it first.
2. **Airplane Mode on, Wi-Fi off.** New WhatsApp messages then wait on WhatsApp's servers and arrive after
   the restore.
3. Keep the iPhone **unlocked and plugged in**.

```bash
scripts/08-restore-iphone.sh    # asks you to type RESTORE; ≈20-40 min; the iPhone reboots by itself
```

### 9. After the reboot
1. Unlock the iPhone and finish any setup screens.
2. Turn **Airplane Mode off**.
3. Open **WhatsApp**:
   - if it asks you to verify your number, do so
   - **if it offers "Restore chat history" from iCloud, tap Skip**.
4. Check these:
   - old chats and groups, with the right senders
   - **tap old photos and PDFs**
   - have someone message you; it should appear **in the same chat** as their history.
5. Turn **Find My iPhone** and **App Store updates** back on.
6. Optional but recommended: in WhatsApp, go to **Settings → Chats → Chat Backup → Back Up Now**, so the
   migrated history is also in iCloud.
7. When happy, delete the sensitive copies:
   ```bash
   scripts/cleanup.sh          # keeps ~/WA-Transfer/android/Media (your media archive); --all removes it too
   ```
   Also delete your key file or screenshot.

### Undo
```bash
scripts/undo.sh               # puts the backup back exactly as the iPhone wrote it
scripts/08-restore-iphone.sh  # the iPhone returns to its state at backup time
```

---

## Troubleshooting (most common)

| Problem | Fix |
|---|---|
| `adb` lists no device | USB debugging is off, or the phone's prompt wasn't accepted. Re-plug and tap **Allow**. Try another cable. |
| "No msgstore.db.crypt15" | End-to-end encrypted backup with the **64-digit key** is not on, or you didn't tap **Back up** afterwards. |
| Decryption fails | The key is wrong or mistyped. Use `--screenshot`. A key made *after* the backup won't open it, so tap **Back up** again. |
| Restore error **211** | Find My iPhone is still on. Turn it off and run again; nothing was changed. |
| "Timeout waiting for SpringBoard" | Force-restart the iPhone (volume up, volume down, hold side button), unlock it, run again. |
| `05-calibrate.sh`: no native example | Send or receive the missing photo or PDF, then `04-backup-iphone.sh` and `05-calibrate.sh` again. |

More: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## FAQ

**Does it work on Windows or Linux?** Not yet. The importer uses Apple's Core Data; it needs a Mac.

**WhatsApp Business?** Not yet. It uses a different app group (`WhatsAppSMB`) and Android package
(`com.whatsapp.w4b`).

**Will my existing iPhone WhatsApp chats be lost?** No. Imported history is merged into existing chats in
date order. Chats the iPhone already has stay, including groups WhatsApp synced at registration.

**Does WhatsApp detect anything?** The result is a normal WhatsApp database restored from a normal iPhone
backup. Nothing is sent to WhatsApp's servers, and nothing is re-sent to your contacts. Old outgoing media
is marked as already sent.

**Why do I need to send myself a photo and a PDF?** The internal flags for sent and received media differ,
and they change between WhatsApp versions. Copying them from your own phone means nothing is guessed.

## Project layout
```
scripts/   00-setup … 08-restore, undo, cleanup   (run in order; each checks its prerequisites)
tools/     media_inject.py      photos + documents: learn from native rows, add files to the backup
           shim_lid.sql         Android msgstore -> watoi input, keyed by LID like current WhatsApp iOS
           post_lid.sh          make imported rows look native; leave synced group members alone
           extract_model.swift  recover WhatsApp's Core Data model from ChatStorage.sqlite (Z_MODELCACHE)
           pdfthumb.swift       PDF page count + page-1 thumbnail (PDFKit)
           verify_backup.py     independent pre-restore verification
           analyze_msgstore.py  what will transfer (counts only)
third_party/  watoi (Core Data importer), sticker_inject.py — GPL-3.0, with provenance notes
tests/     offline tests on synthetic data (tests/run_tests.sh)
docs/      HOW-IT-WORKS, WHATSAPP-IOS-FORMAT, TROUBLESHOOTING, reference schemas
requirements.txt  Python packages (installed into .venv by scripts/00-setup.sh)
```

## Roadmap
- Videos, voice notes and GIFs. The mechanism is the same; it needs calibration examples and `ZMOVIEDURATION` handling.
- Reactions, replies (quote bubbles), edited messages.
- WhatsApp Business.
- Newer WhatsApp versions: please open an issue with your versions and the output of `05-calibrate.sh`.
  It contains no personal data, and IDs are masked.

## Contributing
Reports from real migrations are the most valuable contribution. Include the phone models, OS and WhatsApp
versions on both sides, and the output of `03-analyze.sh`, `05-calibrate.sh` and `07-verify.sh`. **Never
attach databases, backups, keys, screenshots of chats, phone numbers or LIDs.**

## Licence
GPL-3.0-or-later for original code; included third-party code keeps its GPL-3.0 licence (see
[CREDITS.md](CREDITS.md)). Use it only on your own data and devices. WhatsApp is a trademark of Meta
Platforms, Inc.; this project is not affiliated with Meta or Apple.
