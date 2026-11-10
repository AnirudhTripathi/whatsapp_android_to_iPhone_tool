#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Independent pre-restore check of a modified backup, against the untouched originals.

usage: verify_backup.py <backup_udid_dir> <originals_dir> <converted ChatStorage.sqlite>

Checks:
  * ChatStorage.sqlite inside the backup is byte-identical to the converted copy and passes integrity_check
  * Manifest.db passes integrity_check; every row's MBFile RelativePath matches its row
  * every file row (all domains) has a payload on disk
  * every WhatsApp row that is NEW or CHANGED versus the original Manifest.db has a payload of exactly the
    size its MBFile records, and all its parent directories are listed
Size differences in rows we never touched come from iOS itself (live databases change while they are
being backed up - well under 1% of files on a real device); they are reported but are not failures.
Exit code 0 = safe to restore, 1 = problems found.
"""
import hashlib
import os
import plistlib
import shutil
import sqlite3
import sys
import tempfile

DOMAIN = "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
CHATSTORAGE_ID = hashlib.sha1(f"{DOMAIN}-ChatStorage.sqlite".encode()).hexdigest()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def mbinfo(blob):
    arc = plistlib.loads(blob)
    objs = arc["$objects"]
    info = objs[arc["$top"]["root"].data]
    return info, objs[info["RelativePath"].data]


def main():
    udir, orig_dir, converted = sys.argv[1:4]
    problems = []
    payload = lambda fid: os.path.join(udir, fid[:2], fid)

    cs_in_backup = payload(CHATSTORAGE_ID)
    if sha256(cs_in_backup) != sha256(converted):
        problems.append("ChatStorage.sqlite in the backup is not the converted copy")
    with tempfile.TemporaryDirectory() as t:           # check a copy: opening a WAL db may create side files
        c = os.path.join(t, "cs.sqlite")
        shutil.copyfile(cs_in_backup, c)
        integ = sqlite3.connect(c).execute("pragma integrity_check").fetchone()[0]
    print(f"ChatStorage.sqlite integrity: {integ}")
    if integ != "ok":
        problems.append("ChatStorage.sqlite integrity_check failed")

    cur = sqlite3.connect(f"file:{os.path.join(udir, 'Manifest.db')}?immutable=1", uri=True)
    orig = sqlite3.connect(f"file:{os.path.join(orig_dir, 'Manifest.db')}?immutable=1", uri=True)
    integ = cur.execute("pragma integrity_check").fetchone()[0]
    print(f"Manifest.db integrity: {integ}")
    if integ != "ok":
        problems.append("Manifest.db integrity_check failed")
    original_rows = {fid: blob for fid, blob in orig.execute("select fileID, file from Files")}

    rels = set()
    counts = dict(files=0, missing=0, ours=0, ours_bad=0, native_mismatch=0, path_mismatch=0, dirs_missing=0)
    rows = cur.execute("select fileID, domain, relativePath, flags, file from Files").fetchall()
    for fid, dom, rel, flags, blob in rows:
        if dom == DOMAIN:
            rels.add(rel)
    for fid, dom, rel, flags, blob in rows:
        info, inner_rel = mbinfo(blob)
        if inner_rel != rel:
            counts["path_mismatch"] += 1
        if flags != 1:
            continue
        counts["files"] += 1
        p = payload(fid)
        if not os.path.exists(p):
            counts["missing"] += 1
            continue
        size_ok = os.path.getsize(p) == info.get("Size")
        ours = dom == DOMAIN and original_rows.get(fid) != blob
        if ours:
            counts["ours"] += 1
            if not size_ok:
                counts["ours_bad"] += 1
            parent = rel.rsplit("/", 1)[0] if "/" in rel else ""
            while parent:
                if parent not in rels:
                    counts["dirs_missing"] += 1
                    break
                parent = parent.rsplit("/", 1)[0] if "/" in parent else ""
        elif not size_ok:
            counts["native_mismatch"] += 1

    print(f"backup files listed: {counts['files']:,}   payloads missing: {counts['missing']}")
    print(f"WhatsApp entries added/changed by the conversion: {counts['ours']:,}   bad size: {counts['ours_bad']}   "
          f"missing parent directory rows: {counts['dirs_missing']}")
    print(f"RelativePath mismatches: {counts['path_mismatch']}")
    print(f"untouched entries whose size iOS recorded differently (normal, informational): {counts['native_mismatch']}")
    if counts["missing"]:
        problems.append(f"{counts['missing']} payload files missing")
    if counts["ours_bad"]:
        problems.append(f"{counts['ours_bad']} added/changed files have the wrong size")
    if counts["dirs_missing"]:
        problems.append(f"{counts['dirs_missing']} added files lack a parent directory row")
    if counts["path_mismatch"]:
        problems.append(f"{counts['path_mismatch']} MBFile RelativePath mismatches")

    if problems:
        print("\nNOT SAFE TO RESTORE:\n  - " + "\n  - ".join(problems))
        sys.exit(1)
    print("\nAll checks passed: safe to restore.")


if __name__ == "__main__":
    main()
