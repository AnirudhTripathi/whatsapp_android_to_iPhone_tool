#!/usr/bin/env python3
"""Inject Android sticker files into an unencrypted iOS backup and link them to the imported messages.

For every imported sticker message whose .webp still exists on the Android phone:
  * copy the file into the backup under Message/Media/<chat jid>/<a>/<b>/<uuid>.webp (one copy per chat+sticker)
  * add Manifest.db rows (file + directory MBFile plists) so the restore lays the file down
  * add a ZWAMEDIAITEM row and turn the message into type 15 (sticker)

usage: sticker_inject.py <ChatStorage.sqlite> <msgstore_shim.db> <sticker_files_dir> <backup_udid_dir> <baseline_msg_pk> [--dry]
"""
import sys, os, sqlite3, hashlib, base64, uuid, plistlib, shutil, time, glob

DOMAIN = "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
FLAGS_IN, FLAGS_OUT = 83886080, 16781376     # observed on real iOS sticker messages
STICKER_TYPE = 15                             # iOS ZMESSAGETYPE for stickers
MODE_FILE, MODE_DIR = 33188, 16877            # 0100644 / 040755
UID = plistlib.UID

def mbfile(relpath, size, inode, t, is_dir=False, xattr=None):
    """Build the NSKeyedArchiver 'MBFile' blob stored in Manifest.db.Files.file"""
    info = {"$class": UID(4 if xattr else 3), "Birth": t, "Flags": 0, "GroupID": 501, "InodeNumber": inode,
            "LastModified": t, "LastStatusChange": t, "Mode": MODE_DIR if is_dir else MODE_FILE,
            "ProtectionClass": 0 if is_dir else 3, "RelativePath": UID(2), "Size": size, "UserID": 501}
    objs = ["$null", info, relpath]
    if xattr:
        info["ExtendedAttributes"] = UID(3)
        objs.append(plistlib.dumps(xattr, fmt=plistlib.FMT_BINARY))
    objs.append({"$classes": ["MBFile", "NSObject"], "$classname": "MBFile"})
    return plistlib.dumps({"$version": 100000, "$archiver": "NSKeyedArchiver", "$top": {"root": UID(1)}, "$objects": objs},
                          fmt=plistlib.FMT_BINARY)

def fid(relpath):
    return hashlib.sha1(f"{DOMAIN}-{relpath}".encode()).hexdigest()

def main():
    chat_db, shim_db, files_dir, backup_dir, baseline = sys.argv[1:6]
    baseline = int(baseline); dry = "--dry" in sys.argv
    local_files = {os.path.basename(p): p for p in glob.glob(os.path.join(files_dir, "**", "*"), recursive=True) if os.path.isfile(p)}

    cs = sqlite3.connect(chat_db); sh = sqlite3.connect(shim_db)
    mf = sqlite3.connect(os.path.join(backup_dir, "Manifest.db"))
    sess = dict(cs.execute("select Z_PK, ZCONTACTJID from ZWACHATSESSION"))
    msgmap = {(sess.get(s), stanza): (pk, fromme) for pk, s, stanza, fromme in
              cs.execute("select Z_PK, ZCHATSESSION, ZSTANZAID, ZISFROMME from ZWAMESSAGE where Z_PK>?", (baseline,))}
    rows = sh.execute("""select ms.key_remote_jid, ms.key_id, mm.file_path
                         from messages ms join message_media mm on mm.message_row_id=ms._id
                         join sticker_present sp on sp.file_path=mm.file_path
                         where ms.orig_type=20 and ms.status<>6""").fetchall()
    existing = set(r[0] for r in mf.execute("select relativePath from Files where domain=?", (DOMAIN,)))
    ent = cs.execute("select Z_ENT from Z_PRIMARYKEY where Z_NAME='WAMediaItem'").fetchone()[0]
    next_pk = cs.execute("select Z_MAX from Z_PRIMARYKEY where Z_NAME='WAMediaItem'").fetchone()[0] + 1
    inode = 9000000; t = int(time.time())
    copies, manifest_rows = {}, []
    linked = missing_msg = missing_file = 0

    def ensure_dir(rel):
        nonlocal inode
        if rel in existing: return
        parent = rel.rsplit("/", 1)[0]
        if parent.count("/") >= 2: ensure_dir(parent)
        inode += 1
        manifest_rows.append((fid(rel), DOMAIN, rel, 2, mbfile(rel, 0, inode, t, is_dir=True)))
        existing.add(rel)

    for jid, key_id, apath in rows:
        hit = msgmap.get((jid, key_id))
        if not hit: missing_msg += 1; continue
        pk, isfromme = hit
        src = local_files.get(os.path.basename(apath))
        if not src: missing_file += 1; continue
        k = (jid, apath)
        if k not in copies:
            data = open(src, "rb").read()
            u = str(uuid.uuid4())
            local = f"Media/{jid}/{u[0]}/{u[1]}/{u}.webp"; rel = "Message/" + local
            ensure_dir(f"Message/Media/{jid}"); ensure_dir(f"Message/Media/{jid}/{u[0]}"); ensure_dir(f"Message/Media/{jid}/{u[0]}/{u[1]}")
            inode += 1; f = fid(rel)
            if not dry:
                os.makedirs(os.path.join(backup_dir, f[:2]), exist_ok=True)
                shutil.copyfile(src, os.path.join(backup_dir, f[:2], f))
            manifest_rows.append((f, DOMAIN, rel, 1, mbfile(rel, len(data), inode, t, xattr={"com.whatsapp.original": local.encode()})))
            copies[k] = (local, len(data), base64.b64encode(hashlib.sha256(data).digest()).decode())
        local, size, h = copies[k]
        mpk = next_pk; next_pk += 1
        cs.execute("""insert into ZWAMEDIAITEM (Z_PK, Z_ENT, Z_OPT, ZFILESIZE, ZMEDIAORIGIN, ZMOVIEDURATION, ZMESSAGE,
                      ZASPECTRATIO, ZHACCURACY, ZLATITUDE, ZLONGITUDE, ZMEDIALOCALPATH, ZVCARDSTRING, ZVCARDNAME)
                      values (?,?,1,?,0,0,?,0.0,0.0,0.0,0.0,?,'image/webp',?)""", (mpk, ent, size, pk, local, h))
        cs.execute("update ZWAMESSAGE set ZMEDIAITEM=?, ZMESSAGETYPE=?, ZTEXT=NULL, ZFLAGS=? where Z_PK=?",
                   (mpk, STICKER_TYPE, FLAGS_OUT if isfromme else FLAGS_IN, pk))
        linked += 1
    cs.execute("update Z_PRIMARYKEY set Z_MAX=? where Z_NAME='WAMediaItem'", (next_pk - 1,))
    if dry:
        cs.rollback()
    else:
        cs.commit()
        mf.executemany("insert or replace into Files (fileID, domain, relativePath, flags, file) values (?,?,?,?,?)", manifest_rows)
        mf.commit()
    print(f"stickers linked={linked} files_copied={len(copies)} manifest_rows={len(manifest_rows)} "
          f"no_matching_message={missing_msg} file_not_on_android={missing_file}")

if __name__ == "__main__":
    main()
