# SPDX-License-Identifier: GPL-3.0-or-later
"""Offline tests: synthetic data only, no phones, no personal data.  run: tests/run_tests.sh"""
import hashlib
import os
import plistlib
import sqlite3
import subprocess
import sys
import tempfile
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import media_inject as mi  # noqa: E402

UID = plistlib.UID


def native_like_mbfile(rel, size, is_dir=False):
    """MBFile archive shaped like the ones iOS 27 writes for WhatsApp media (no xattrs, no digest)."""
    info = {"$class": UID(3), "Birth": 1, "Flags": 0, "GroupID": 501, "InodeNumber": 1, "LastModified": 1,
            "LastStatusChange": 1, "Mode": 0o40775 if is_dir else 0o100644,
            "ProtectionClass": 0 if is_dir else 3, "RelativePath": UID(2), "Size": size, "UserID": 501}
    return plistlib.dumps({"$version": 100000, "$archiver": "NSKeyedArchiver", "$top": {"root": UID(1)},
                           "$objects": ["$null", info, rel, {"$classname": "MBFile", "$classes": ["MBFile", "NSObject"]}]},
                          fmt=plistlib.FMT_BINARY)


class BackupFormat(unittest.TestCase):
    def test_chatstorage_file_id(self):
        self.assertEqual(mi.file_id("ChatStorage.sqlite"), "7c7fba66680ef796b916b067077cc246adacf01d")

    def test_build_mbfile_rewrites_path_size_inode(self):
        tmpl = native_like_mbfile("Message/Media/x@lid/a/b/old.jpg", 10)
        blob = mi.build_mbfile(tmpl, "Message/Media/y@lid/c/d/new.jpg", 12345, 777, 1700000000)
        s = mi.mbfile_summary(blob)
        self.assertEqual(s["RelativePath"], "Message/Media/y@lid/c/d/new.jpg")
        self.assertEqual((s["Size"], s["InodeNumber"], s["LastModified"]), (12345, 777, 1700000000))
        self.assertEqual((s["Mode"], s["ProtectionClass"]), (oct(0o100644), 3))
        self.assertNotIn("ExtendedAttributes", s)

    def test_hash_matches_whatsapp_convention(self):
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(b"hello whatsapp")
        try:
            import base64
            want = base64.b64encode(hashlib.sha256(b"hello whatsapp").digest()).decode()
            self.assertEqual(mi.b64_sha256(f.name), want)
        finally:
            os.remove(f.name)


class Captions(unittest.TestCase):
    def test_document_name_is_not_a_caption(self):
        self.assertIsNone(mi.doc_caption(None, "Report.pdf", "Report.pdf"))
        self.assertIsNone(mi.doc_caption(None, "Report", "Report.pdf"))
        self.assertEqual(mi.doc_caption(None, "see page 3", "Report.pdf"), "see page 3")
        self.assertEqual(mi.doc_caption("real caption", "Report.pdf", "Report.pdf"), "real caption")


class Images(unittest.TestCase):
    def test_dimensions_and_thumbnail(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as t:
            src, dst = os.path.join(t, "a.jpg"), os.path.join(t, "a.thumb")
            Image.new("RGB", (1536, 1506), "red").save(src)
            self.assertEqual(mi.image_dims_and_thumb(src, dst, 72), (1536, 1506))   # width, height
            with Image.open(dst) as th:
                self.assertEqual((th.format, max(th.size)), ("JPEG", 72))


class LidShim(unittest.TestCase):
    """shim_lid.sql on a tiny synthetic msgstore.db with the modern Android schema."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.tmp.name, "msgstore.db")
        c = sqlite3.connect(self.db)
        c.executescript("""
        create table jid(_id integer primary key, user text, server text, raw_string text, type integer);
        create table jid_map(lid_row_id integer, jid_row_id integer, sort_id integer);
        create table chat(_id integer primary key, jid_row_id integer, subject text, archived integer,
                          created_timestamp integer, sort_timestamp integer, last_message_row_id integer);
        create table message(_id integer primary key, chat_row_id integer, from_me integer, key_id text,
                             sender_jid_row_id integer, status integer, timestamp integer, message_type integer,
                             text_data text, starred integer);
        create table message_media(message_row_id integer, file_path text, media_caption text, mime_type text,
                                   media_name text, file_size integer, width integer, height integer);
        create table message_event(message_row_id integer, name text, description text);
        create table group_participant_user(group_jid_row_id integer, user_jid_row_id integer, rank integer);
        insert into jid values (1,'111','s.whatsapp.net','111@s.whatsapp.net',0),   -- Alice by phone
                               (2,'9001','lid','9001@lid',0),                       -- Alice's LID
                               (3,'222','s.whatsapp.net','222@s.whatsapp.net',0),   -- Bob (no LID known)
                               (4,'333-1','g.us','333-1@g.us',0),                   -- a group
                               (5,'9002','lid','9002@lid',0),                       -- Carol (LID only, in group)
                               (6,'444','s.whatsapp.net','444@s.whatsapp.net',0);   -- Carol's phone
        insert into jid_map values (2,1,1),(5,6,1);
        insert into chat values (1,1,null,0,0,0,11),(2,3,null,0,0,0,12),(3,4,'Family',0,0,0,14),(4,2,null,0,0,0,15);
        insert into message values
          (11,1,0,'K1',null,0,1000,0,'hi from alice (old phone chat)',0),
          (12,2,1,'K2',null,0,2000,0,'hi bob',0),
          (13,3,0,'K3',5,0,3000,0,'carol in group',0),
          (14,3,0,'K4',6,0,4000,1,null,0),
          (15,4,0,'K5',null,0,5000,0,'hi from alice (new lid chat)',0),
          (16,1,0,'K6',null,0,6000,7,null,0);                                      -- system notice
        insert into message_media values (14,'Media/WhatsApp Images/IMG-1.jpg','a caption','image/jpeg',null,10,4,3);
        insert into group_participant_user values (4,6,0),(4,2,1);
        """)
        c.commit()
        with open(os.path.join(REPO, "tools", "shim_lid.sql")) as f:
            c.executescript(f.read())
        c.commit()
        self.c = c

    def tearDown(self):
        self.c.close()
        self.tmp.cleanup()

    def q(self, sql):
        return self.c.execute(sql).fetchall()

    def test_one_to_one_keyed_by_lid_with_phone_identifier(self):
        rows = dict(self.q("select raw_string_jid, phone_jid from chat_view where server in ('s.whatsapp.net','lid')"))
        self.assertEqual(rows["9001@lid"], "111@s.whatsapp.net")        # phone chat mapped to LID
        self.assertIn("222@s.whatsapp.net", rows)                         # no mapping -> stays phone
        self.assertEqual(self.q("select phone from canon_phone where canon='9001@lid'")[0][0], "111@s.whatsapp.net")

    def test_old_and_new_chat_of_same_person_merge(self):
        n = self.q("select count(*) from messages where key_remote_jid='9001@lid' and status<>6")[0][0]
        self.assertEqual(n, 2)

    def test_group_senders_and_participants_use_lid(self):
        senders = {r[0] for r in self.q("select remote_resource from messages where key_remote_jid='333-1@g.us'")}
        self.assertEqual(senders, {"9002@lid"})
        parts = {r[0] for r in self.q("select jid from group_participants where gjid='333-1@g.us'")}
        self.assertEqual(parts, {"9002@lid", "9001@lid"})

    def test_system_notices_skipped_and_captions_kept(self):
        self.assertEqual(self.q("select status from messages where key_id='K6'")[0][0], 6)
        self.assertEqual(self.q("select media_caption, media_wa_type from messages where key_id='K4'")[0], ("a caption", 1))


class Helpers(unittest.TestCase):
    BUILD = os.path.join(REPO, "build")

    @unittest.skipUnless(os.path.exists(os.path.join(REPO, "build", "extract_model")), "run scripts/00-setup.sh")
    def test_model_recovered_from_core_data_store(self):
        with tempfile.TemporaryDirectory() as t:
            out = subprocess.run([os.path.join(self.BUILD, "extract_model"), "selftest", os.path.join(t, "st")],
                                 capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertIn("compatible=true", out.stdout)

    @unittest.skipUnless(os.path.exists(os.path.join(REPO, "build", "pdfthumb")), "run scripts/00-setup.sh")
    def test_pdf_pages_and_thumbnail(self):
        with tempfile.TemporaryDirectory() as t:
            pdf, thumb = os.path.join(t, "two.pdf"), os.path.join(t, "two.thumb")
            write_two_page_pdf(pdf)
            out = subprocess.run([os.path.join(self.BUILD, "pdfthumb")], input=f"{pdf}\t{thumb}\t96\n",
                                 capture_output=True, text=True).stdout.strip().split("\t")
            self.assertEqual(out[1:], ["2", "ok"])
            from PIL import Image
            with Image.open(thumb) as im:
                self.assertEqual(max(im.size), 96)


def write_two_page_pdf(path):
    objs = ["<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>"]
    out, offsets = b"%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{o}\nendobj\n".encode()
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    with open(path, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
