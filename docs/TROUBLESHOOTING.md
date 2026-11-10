# Troubleshooting

Every problem below was hit during real migrations.

## Move to iOS
**"Move to iOS keeps failing, can I still use it?"** It needs a brand-new or factory-reset iPhone, both
phones on the same Wi-Fi (or the Android phone on the iPhone's hotspot), regular WhatsApp (not Business),
and both phones untouched during the transfer. If it still fails, this project is the alternative.

## Android
| Symptom | Cause / fix |
|---|---|
| `adb devices` is empty, but the Mac sees the phone over USB | USB debugging is off. Samsung: **Settings → About phone → Software information → tap Build number 7×**, then **Developer options → USB debugging**. Re-plug, tap **Allow**. |
| Device shows `unauthorized` | Accept the prompt on the phone. Tick *Always allow*. |
| `adb pull` stalls or the phone disconnects | Try another cable or port, avoid hubs, or use **Wireless debugging** (Developer options). Enable *Stay awake*. |
| Only `msgstore.db.crypt14` files, no `.crypt15` | End-to-end encrypted backup is off, or you didn't tap **Back up** after turning it on. |
| WhatsApp Business account | Not supported yet (`com.whatsapp.w4b`). |
| Fewer media files than the Google Drive backup size suggested | The Drive backup also held media you have since deleted from the phone. Only files still on the phone can be linked. `03-analyze.sh` shows "file deleted" and "never downloaded" counts. |

## Decryption
| Symptom | Cause / fix |
|---|---|
| "key file must contain 64 hex digits (found 58)" | The key was copied with text recognition, which can insert look-alike letters. The script fixes the common ones. If digits are still missing, use `--screenshot` with the original screenshot. |
| "Authentication tag mismatch" / "key does not match" | Wrong key, a misread digit, or a key created after the backup was written. Try `--screenshot` (it repairs near misses), or tap **Back up** again in WhatsApp and re-pull. |
| You chose a password instead of the 64-digit key | Password backups can't be decrypted offline. Settings → Chats → Chat backup → End-to-end encrypted backup → *Change* → use a 64-digit key → **Back up**. |

## iPhone backup
| Symptom | Cause / fix |
|---|---|
| "Backup encryption is ON" | Finder → iPhone → untick **Encrypt local backup** (needs the backup password). |
| "ChatStorage.sqlite is not in the backup" | WhatsApp isn't registered on the iPhone yet. |
| `05-calibrate.sh`: missing example | Send *and* receive one photo and one PDF, wait for the ticks, then run `04-backup-iphone.sh` (incremental) and `05-calibrate.sh` again. |
| Not enough disk space | `export WA_WORK=/Volumes/<external APFS drive>/WA-Transfer` and start again from step 2. |

## Conversion
| Symptom | Cause / fix |
|---|---|
| `extract_model`: "no model cache" or "not compatible" | Very unusual. Make sure the backup is from the WhatsApp version that is installed. Open an issue with the output. |
| watoi: `NSInvalidArgumentException … nil key` | You ran an unpatched watoi. Use `build/watoi` from `00-setup.sh`. |
| `07-verify.sh`: "untouched entries whose size iOS recorded differently" | Informational. iOS records sizes while live databases change. Only problems in **added/changed** entries fail the check. |

## Restore
| Symptom | Cause / fix |
|---|---|
| `MBErrorDomain/211`, "Find My iPhone must be disabled" | Turn off Find My iPhone, then run again. Nothing was changed. If the switch is grey: Screen Time → Content & Privacy Restrictions → allow changes, and clear any "Update Apple ID settings" banner. |
| "Timeout waiting for SpringBoard" (`MBErrorDomain/1`) | Force-restart the iPhone (volume up, volume down, hold side button), unlock it, run again. |
| Setup screens after the reboot | Expected after a restore. Finish them; your data is there. |

## After the restore
| Symptom | Cause / fix |
|---|---|
| WhatsApp offers "Restore chat history" from iCloud | Tap **Skip**. Restoring would replace the imported history. |
| Chat list empty | Open an issue with `07-verify.sh` output. As a workaround: WhatsApp → Settings → Chats → Chat Backup → Back Up Now, delete and reinstall WhatsApp, register, then **Restore** from that iCloud backup. |
| A chat shows a number instead of a name | The contact isn't in your address book, or WhatsApp hasn't learned their LID yet. Grant WhatsApp Contacts access; names fill in as contacts sync. |
| An old photo or document shows a placeholder | Its file wasn't on the Android phone (deleted or never downloaded). |
| A contact's new message opens a second chat | Please report it with your WhatsApp versions. Chats are keyed by LID to prevent exactly this. |

## Undo
```bash
scripts/undo.sh && scripts/08-restore-iphone.sh
```
This returns the iPhone to its state at backup time.
