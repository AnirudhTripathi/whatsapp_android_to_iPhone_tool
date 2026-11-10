#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Turn imported "<image>" / "<document>" placeholder messages into real, tappable WhatsApp media
inside an UNENCRYPTED iPhone backup. Runs after watoi + post_lid.sh (+ sticker_inject.py).

Every convention is learned from media the user sent/received natively on the iPhone before the
backup ("calibration") - nothing version-specific is hard-coded. Observed on WhatsApp iOS 26.44.72:
  image item:  ZLATITUDE=height, ZLONGITUDE=width, ZXMPPTHUMBPATH=<uuid>.thumb (JPEG, ~72px),
               ZVCARDNAME=base64(sha256(file)), ZVCARDSTRING=mime, ZTITLE=caption
  document:    ZAUTHORNAME=file name, ZMOVIEDURATION=PDF page count, PDF .thumb = page 1 (~96px)
  message:     ZMESSAGETYPE 1/8, ZMEDIASECTIONID 'YYYY-MM' / 'doc-YYYY-MM', ZFLAGS per direction
  backup:      Message/Media/<chat jid>/<u0>/<u1>/<uuid>.<ext>, MBFile cloned from a native media row
Mechanism generalises sticker_inject.py of MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset.

usage:
  media_inject.py calibrate <ChatStorage.sqlite> <backup_udid_dir> <baseline_msg_pk>
  media_inject.py inject    <ChatStorage.sqlite> <msgstore_lid.db> <android_root> <backup_udid_dir>
                            <baseline_msg_pk> <work_dir> [--types image,document] [--only-chat JID]
                            [--limit N] [--dry]
"""
import argparse, base64, datetime as dt, hashlib, os, plistlib, shutil, sqlite3, subprocess, sys, time, uuid
from collections import Counter

DOMAIN = "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
IOS_TYPE = {"image": 1, "document": 8}
ANDROID_TYPE = {"image": 1, "document": 9}      # view-once (42/43) intentionally left as placeholders
COCOA_EPOCH = 978307200
UID = plistlib.UID
PDFTHUMB = os.environ.get("WA_PDFTHUMB") or os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "pdfthumb")


def q(con, sql, *a):
    return con.execute(sql, a).fetchall()


def cols(con, table):
    return [r[1] for r in con.execute(f"PRAGMA table_info({table})")]


def file_id(rel):
    return hashlib.sha1(f"{DOMAIN}-{rel}".encode()).hexdigest()


def decode_mbfile(blob):
    arc = plistlib.loads(blob)
    objs = arc["$objects"]
    return arc, objs[arc["$top"]["root"].data], objs


def mbfile_summary(blob):
    _, info, objs = decode_mbfile(blob)
    out = {}
    for k, v in info.items():
        if k == "$class":
            continue
        if isinstance(v, UID):
            t = objs[v.data]
            out[k] = f"<{len(t)} bytes>" if isinstance(t, (bytes, bytearray)) else t
        else:
            out[k] = oct(v) if k == "Mode" else v
    return out


def b64_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return base64.b64encode(h.digest()).decode()


def manifest_row(mf, rel):
    return mf.execute("select fileID, flags, file from Files where domain=? and relativePath=?", (DOMAIN, rel)).fetchone()


# --------------------------------------------------------------------------------------- calibrate
def calibrate(chat_db, backup_dir, baseline, verbose=True):
    """Read-only. Learns conventions from native image/document rows (Z_PK <= baseline)."""
    say = print if verbose else (lambda *a, **k: None)
    cs = sqlite3.connect(f"file:{chat_db}?mode=ro", uri=True)
    cs.row_factory = sqlite3.Row
    mf = sqlite3.connect(f"file:{os.path.join(backup_dir, 'Manifest.db')}?mode=ro", uri=True)
    rows = q(cs, """select m.*, s.ZCONTACTJID as _chatjid from ZWAMESSAGE m join ZWACHATSESSION s on s.Z_PK=m.ZCHATSESSION
                    where m.Z_PK <= ? and m.ZMEDIAITEM is not null and m.ZMESSAGETYPE in (1, 8) order by m.Z_PK""", baseline)
    L = {"msg": {}, "item": {}, "thumb": {}, "mbfile_file": None, "mbfile_dir": None}
    say(f"native image/document messages: {len(rows)}")
    for r in rows:
        kind = "image" if r["ZMESSAGETYPE"] == 1 else "document"
        direction = "out" if r["ZISFROMME"] else "in"
        item = cs.execute("select * from ZWAMEDIAITEM where Z_PK=?", (r["ZMEDIAITEM"],)).fetchone()
        mcols = {k: r[k] for k in r.keys() if r[k] is not None and not k.startswith("_")}
        icols = {k: item[k] for k in item.keys() if item[k] is not None}
        L["msg"].setdefault((kind, direction), mcols)
        if kind == "document" and str(icols.get("ZVCARDSTRING", "")) == "application/pdf":
            L["item"]["document"] = icols              # prefer a PDF as the document template
        L["item"].setdefault(kind, icols)
        say(f"  {kind:8s} {direction:3s} Z_PK={r['Z_PK']} ZFLAGS={r['ZFLAGS']} status={r['ZMESSAGESTATUS']} "
            f"section={r['ZMEDIASECTIONID']} mime={icols.get('ZVCARDSTRING')} "
            f"lat/lon={icols.get('ZLATITUDE')}/{icols.get('ZLONGITUDE')} dur={icols.get('ZMOVIEDURATION')} "
            f"author={'yes' if icols.get('ZAUTHORNAME') else 'no'} title={'yes' if icols.get('ZTITLE') else 'no'} "
            f"thumb={'yes' if icols.get('ZXMPPTHUMBPATH') else 'no'} url={'yes' if icols.get('ZMEDIAURL') else 'no'}")
        for col in ("ZMEDIALOCALPATH", "ZXMPPTHUMBPATH"):
            p = icols.get(col)
            if not p:
                continue
            mr = manifest_row(mf, "Message/" + p)
            if not mr:
                say(f"      {col}: NOT in Manifest.db")
                continue
            fid, flags, blob = mr
            if col == "ZMEDIALOCALPATH" and L["mbfile_file"] is None:
                L["mbfile_file"] = blob
            if L["mbfile_dir"] is None:
                dr = manifest_row(mf, "Message/" + p.rsplit("/", 1)[0])
                if dr:
                    L["mbfile_dir"] = dr[2]
            if col == "ZXMPPTHUMBPATH" and kind not in L["thumb"]:
                payload = os.path.join(backup_dir, fid[:2], fid)
                try:
                    from PIL import Image
                    with Image.open(payload) as im:
                        L["thumb"][kind] = {"max": max(im.size), "format": im.format, "ext": os.path.splitext(p)[1]}
                        say(f"      thumbnail: {im.format} {im.size}")
                except Exception as e:  # noqa: BLE001
                    say(f"      thumbnail unreadable: {e}")
    if L["mbfile_file"]:
        say(f"  MBFile template (file): {mbfile_summary(L['mbfile_file'])}")
    if L["mbfile_dir"]:
        say(f"  MBFile template (dir):  {mbfile_summary(L['mbfile_dir'])}")
    missing = [f"{k}/{d}" for k in ("image", "document") for d in ("in", "out") if (k, d) not in L["msg"]]
    say(f"  directions with no native example: {missing or 'none'}")
    return L


# --------------------------------------------------------------------------------------- building blocks
def build_mbfile(template_blob, rel, size, inode, now):
    """Clone a native MBFile archive; rewrite path/size/inode/times. Native media rows carry no xattrs/digest."""
    arc = plistlib.loads(template_blob)
    objs = arc["$objects"]
    info = objs[arc["$top"]["root"].data]
    objs[info["RelativePath"].data] = rel
    info["Size"] = size
    info["InodeNumber"] = inode
    for k in ("LastModified", "LastStatusChange", "Birth"):
        if k in info:
            info[k] = now
    for k in ("ExtendedAttributes", "Digest"):
        info.pop(k, None)
    return plistlib.dumps(arc, fmt=plistlib.FMT_BINARY)


def image_dims_and_thumb(src, dst, max_side):
    """-> (width, height) in display orientation; writes a JPEG thumbnail if dst is given."""
    from PIL import Image, ImageOps
    with Image.open(src) as im:
        im = ImageOps.exif_transpose(im)
        w, h = im.size
        if dst:
            t = im.convert("RGB") if im.mode not in ("RGB", "L") else im.copy()
            t.thumbnail((max_side, max_side))
            t.save(dst, format="JPEG", quality=80)
        return w, h


def doc_caption(media_caption, text_data, media_name):
    """Android stores the file name as the 'caption' of most documents; keep only real captions."""
    if media_caption:
        return media_caption
    if text_data and not (media_name and text_data in media_name):
        return text_data
    return None


# --------------------------------------------------------------------------------------- inject
def inject(a):
    L = calibrate(a.chat_db, a.backup_dir, a.baseline, verbose=False)
    types = [t.strip() for t in a.types.split(",") if t.strip()]
    for t in types:
        if t not in L["item"]:
            sys.exit(f"no native {t} in the backup to learn from")
        for d in ("in", "out"):
            if (t, d) not in L["msg"] and not a.allow_missing_direction:
                sys.exit(f"no native {t}/{d} example in the backup (send/receive one, back up again), "
                         f"or pass --allow-missing-direction")
    if not L["mbfile_file"] or not L["mbfile_dir"]:
        sys.exit("could not find native media file/dir rows in Manifest.db to clone")

    cs = sqlite3.connect(a.chat_db)
    sh = sqlite3.connect(f"file:{a.shim_db}?mode=ro", uri=True)
    mf = sqlite3.connect(os.path.join(a.backup_dir, "Manifest.db"))
    mmc = set(cols(sh, "message_media"))
    sel = lambda c: f"mm.{c}" if c in mmc else "NULL"

    placeholders = {}
    for pk, jid, stanza, fromme, mdate in q(cs, """select m.Z_PK, s.ZCONTACTJID, m.ZSTANZAID, m.ZISFROMME, m.ZMESSAGEDATE
            from ZWAMESSAGE m join ZWACHATSESSION s on s.Z_PK=m.ZCHATSESSION
            where m.Z_PK > ? and m.ZMESSAGETYPE = 0 and m.ZMEDIAITEM is null""", a.baseline):
        placeholders[(jid, stanza, int(fromme or 0))] = (pk, mdate)

    ent = q(cs, "select Z_ENT from Z_PRIMARYKEY where Z_NAME='WAMediaItem'")[0][0]
    next_pk = q(cs, "select Z_MAX from Z_PRIMARYKEY where Z_NAME='WAMediaItem'")[0][0] + 1
    item_cols = cols(cs, "ZWAMEDIAITEM")
    existing_rel = {r[0] for r in mf.execute("select relativePath from Files where domain=?", (DOMAIN,))}
    now = int(time.time())
    inode = 7_000_000_000
    thumbs_dir = os.path.join(a.work_dir, "thumbs")
    os.makedirs(thumbs_dir, exist_ok=True)

    stats = Counter()
    plan_items, plan_msgs, plan_manifest, plan_links, pdf_jobs = [], [], [], [], []

    def ensure_dir(rel):
        nonlocal inode
        if rel in existing_rel:
            return
        parent = rel.rsplit("/", 1)[0]
        if parent != rel and "/" in parent:
            ensure_dir(parent)
        inode += 1
        plan_manifest.append((file_id(rel), DOMAIN, rel, 2, build_mbfile(L["mbfile_dir"], rel, 0, inode, now)))
        existing_rel.add(rel)
        stats["new directories"] += 1

    def add_file(src, rel, size):
        nonlocal inode
        inode += 1
        plan_manifest.append((file_id(rel), DOMAIN, rel, 1, build_mbfile(L["mbfile_file"], rel, size, inode, now)))
        plan_links.append((src, os.path.join(a.backup_dir, file_id(rel)[:2], file_id(rel))))

    for kind in types:
        tmpl = L["item"][kind]
        thumb = L["thumb"].get(kind)
        rows = q(sh, f"""select ms.key_remote_jid, ms.key_id, ms.key_from_me, ms.data, {sel('media_caption')},
                                mm.file_path, {sel('mime_type')}, {sel('media_name')}, {sel('width')}, {sel('height')}
                         from messages ms join message_media mm on mm.message_row_id = ms._id
                         where ms.status <> 6 and ms.orig_type = ?""", ANDROID_TYPE[kind])
        for jid, key_id, fromme, text_data, mcap, apath, mime, mname, aw, ah in rows:
            if a.only_chat and jid != a.only_chat:
                continue
            ph = placeholders.get((jid, key_id, int(fromme or 0)))
            if not ph:
                stats[f"{kind}: no matching imported message"] += 1
                continue
            src = os.path.join(a.android_root, apath) if apath else None
            if not src or not os.path.isfile(src) or os.path.getsize(src) == 0:
                stats[f"{kind}: file not on phone -> stays placeholder"] += 1
                continue
            if a.limit and stats[f"{kind}: linked"] >= a.limit:
                continue
            msg_pk, mdate = ph
            u = str(uuid.uuid4())                       # native names are lowercase uuid4
            ext = os.path.splitext(src)[1].lower() or (".jpg" if kind == "image" else "")
            folder = f"Media/{jid}/{u[0]}/{u[1]}"
            local = f"{folder}/{u}{ext}"
            size = os.path.getsize(src)
            ensure_dir("Message/" + folder)
            add_file(src, "Message/" + local, size)

            item = {c: None for c in item_cols}
            item.update({"Z_PK": next_pk, "Z_ENT": ent, "Z_OPT": 1, "ZMESSAGE": msg_pk, "ZFILESIZE": size,
                         "ZMEDIAORIGIN": tmpl.get("ZMEDIAORIGIN", 0), "ZMOVIEDURATION": 0,
                         "ZASPECTRATIO": 0.0, "ZHACCURACY": 0.0, "ZLATITUDE": 0.0, "ZLONGITUDE": 0.0,
                         "ZMEDIAURLDATE": mdate, "ZMEDIALOCALPATH": local, "ZVCARDNAME": b64_sha256(src),
                         "ZVCARDSTRING": mime or tmpl.get("ZVCARDSTRING")})
            month = dt.datetime.fromtimestamp((mdate or 0) + COCOA_EPOCH).strftime("%Y-%m")
            if kind == "image":
                item["ZTITLE"] = mcap or text_data or None
                tname = f"{u}{(thumb or {}).get('ext', '.thumb')}"
                tdst = os.path.join(thumbs_dir, tname) if (thumb and not a.dry) else None
                try:
                    w, h = image_dims_and_thumb(src, tdst, (thumb or {}).get("max", 72))
                except Exception:  # noqa: BLE001  (e.g. HEIC without a decoder)
                    w, h, tdst = (aw or 0), (ah or 0), None
                item["ZLATITUDE"], item["ZLONGITUDE"] = float(h or 0), float(w or 0)
                if thumb and (tdst or a.dry):
                    tlocal = f"{folder}/{tname}"
                    add_file(tdst or src, "Message/" + tlocal, os.path.getsize(tdst) if tdst else 0)
                    item["ZXMPPTHUMBPATH"] = tlocal
                    stats["image thumbnails"] += 1
                section = month
            else:
                item["ZAUTHORNAME"] = mname or os.path.basename(src)
                item["ZTITLE"] = doc_caption(mcap, text_data, mname)
                if (mime == "application/pdf" or ext == ".pdf") and thumb:
                    tname = f"{u}{thumb.get('ext', '.thumb')}"
                    tdst = os.path.join(thumbs_dir, tname)
                    pdf_jobs.append((src, tdst, thumb.get("max", 96), len(plan_items), f"{folder}/{tname}"))
                section = "doc-" + month
            plan_items.append({k: v for k, v in item.items() if k in item_cols})
            tm = L["msg"].get((kind, "out" if fromme else "in")) or {}
            plan_msgs.append((IOS_TYPE[kind], next_pk, tm.get("ZFLAGS"), section, msg_pk))
            next_pk += 1
            stats[f"{kind}: linked"] += 1
            stats[f"{kind}: MB"] += round(size / 1e6)

    # PDF page counts + page-1 thumbnails, in one batch through PDFKit
    if pdf_jobs and not a.dry and os.path.exists(PDFTHUMB):
        inp = "".join(f"{s}\t{d}\t{m}\n" for s, d, m, _, _ in pdf_jobs)
        out = subprocess.run([PDFTHUMB], input=inp, capture_output=True, text=True).stdout.splitlines()
        res = {}
        for line in out:
            parts = line.split("\t")
            if len(parts) == 3:
                res[parts[0]] = (int(parts[1] or 0), parts[2] == "ok")
        for s, d, _, idx, tlocal in pdf_jobs:
            pages, ok = res.get(s, (0, False))
            plan_items[idx]["ZMOVIEDURATION"] = pages
            if ok and os.path.exists(d):
                add_file(d, "Message/" + tlocal, os.path.getsize(d))
                plan_items[idx]["ZXMPPTHUMBPATH"] = tlocal
                stats["pdf thumbnails"] += 1
    elif pdf_jobs:
        stats["pdf thumbnails (planned)"] = len(pdf_jobs)

    print("plan:", dict(stats))
    print(f"manifest rows to add: {len(plan_manifest)}   payload files: {len(plan_links)}")
    for k in ("image", "document"):
        ex = next((it for it in plan_items if it.get("ZMESSAGE") and (it.get("ZAUTHORNAME") is None) == (k == "image")), None)
        if ex:
            print(f"example {k} item:", {c: (v if not isinstance(v, str) or len(v) < 70 else v[:67] + "...")
                                        for c, v in ex.items() if v is not None})
    if a.dry:
        print("DRY RUN: nothing written")
        return

    for src, dst in plan_links:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.exists(dst):
            os.remove(dst)
        try:
            os.link(src, dst)                    # zero extra disk space (same APFS volume)
        except OSError:
            shutil.copyfile(src, dst)
    if plan_items:
        names = list(plan_items[0].keys())
        cs.executemany(f"insert into ZWAMEDIAITEM ({','.join(names)}) values ({','.join('?' * len(names))})",
                       [tuple(it[n] for n in names) for it in plan_items])
    for mtype, mpk, flags, section, msg_pk in plan_msgs:
        cs.execute("""update ZWAMESSAGE set ZMESSAGETYPE=?, ZMEDIAITEM=?, ZTEXT=NULL, ZMEDIASECTIONID=?,
                      ZFLAGS=COALESCE(?, ZFLAGS) where Z_PK=?""", (mtype, mpk, section, flags, msg_pk))
    cs.execute("update Z_PRIMARYKEY set Z_MAX=? where Z_NAME='WAMediaItem'", (next_pk - 1,))
    cs.commit()
    mf.executemany("insert or replace into Files (fileID, domain, relativePath, flags, file) values (?,?,?,?,?)",
                   plan_manifest)
    mf.commit()
    with open(os.path.join(a.work_dir, "media_inject_added_payloads.txt"), "w") as f:
        f.writelines(dst + "\n" for _, dst in plan_links)
    verify(cs, mf, a.backup_dir, a.baseline)


def verify(cs, mf, backup_dir, baseline):
    problems = Counter()
    rows = q(cs, """select m.Z_PK, m.ZMEDIAITEM, i.ZMESSAGE, i.ZMEDIALOCALPATH, i.ZXMPPTHUMBPATH, i.ZFILESIZE
                    from ZWAMESSAGE m left join ZWAMEDIAITEM i on i.Z_PK=m.ZMEDIAITEM
                    where m.Z_PK > ? and m.ZMESSAGETYPE in (1, 8)""", baseline)
    rels = {r[0]: r[1] for r in mf.execute("select relativePath, fileID from Files where domain=?", (DOMAIN,))}
    for pk, item, back, path, thumb, size in rows:
        if item is None or back != pk:
            problems["message<->item link broken"] += 1
        for p, want in ((path, size), (thumb, None)):
            if not p:
                continue
            rel = "Message/" + p
            if rel not in rels:
                problems["file missing from Manifest.db"] += 1
                continue
            payload = os.path.join(backup_dir, rels[rel][:2], rels[rel])
            if not os.path.exists(payload):
                problems["payload missing"] += 1
            elif want is not None and os.path.getsize(payload) != want:
                problems["size mismatch"] += 1
            parent = rel.rsplit("/", 1)[0]
            while "/" in parent:
                if parent not in rels:
                    problems["directory row missing"] += 1
                    break
                parent = parent.rsplit("/", 1)[0]
    zmax = q(cs, "select Z_MAX from Z_PRIMARYKEY where Z_NAME='WAMediaItem'")[0][0]
    if zmax < q(cs, "select coalesce(max(Z_PK),0) from ZWAMEDIAITEM")[0][0]:
        problems["Z_MAX below max Z_PK"] += 1
    print(f"verify: {len(rows)} imported image/document messages; integrity={q(cs, 'pragma integrity_check')[0][0]}; "
          f"problems={dict(problems) or 'none'}")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("calibrate")
    c.add_argument("chat_db"); c.add_argument("backup_dir"); c.add_argument("baseline", type=int)
    i = sub.add_parser("inject")
    for n in ("chat_db", "shim_db", "android_root", "backup_dir"):
        i.add_argument(n)
    i.add_argument("baseline", type=int); i.add_argument("work_dir")
    i.add_argument("--types", default="image,document"); i.add_argument("--only-chat")
    i.add_argument("--limit", type=int, default=0); i.add_argument("--dry", action="store_true")
    i.add_argument("--allow-missing-direction", action="store_true")
    a = p.parse_args()
    if a.cmd == "calibrate":
        calibrate(a.chat_db, a.backup_dir, a.baseline)
    else:
        inject(a)


if __name__ == "__main__":
    main()
