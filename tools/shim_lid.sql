-- SPDX-License-Identifier: GPL-3.0-or-later (derived from GPL-3.0 code, see CREDITS.md)
-- LID-aware variant of MdShahnawazSheikh/whatsapp-android-to-iphone-no-reset scripts/shim.sql (GPL-3.0).
-- Builds the legacy tables watoi reads, on a COPY of a modern Android msgstore.db, but keys people the
-- way current WhatsApp for iOS does (verified on a real iPhone, WA 26.44.72 / iOS 27.2):
--   * 1:1 chats   -> ZCONTACTJID = <lid>@lid  (phone JID kept separately for ZCONTACTIDENTIFIER)
--   * group senders / participants -> <lid>@lid  (so they match the members WhatsApp already synced)
--   * groups      -> <id>@g.us (unchanged)
-- Falls back to the phone JID only when Android has no LID mapping for that person.
PRAGMA journal_mode=DELETE;

-- canonical id (LID where known) and phone id for every jid row
CREATE TABLE jid_canon AS
SELECT j._id AS jid_row_id,
       CASE
         WHEN j.server = 'lid' THEN j.raw_string
         WHEN j.server = 's.whatsapp.net' THEN COALESCE(
              (SELECT l.raw_string FROM jid_map m JOIN jid l ON l._id = m.lid_row_id
                WHERE m.jid_row_id = j._id AND l.server = 'lid' ORDER BY m.sort_id DESC LIMIT 1),
              j.raw_string)
         ELSE j.raw_string END AS canon,
       CASE
         WHEN j.server = 's.whatsapp.net' THEN j.raw_string
         WHEN j.server = 'lid' THEN
              (SELECT p.raw_string FROM jid_map m JOIN jid p ON p._id = m.jid_row_id
                WHERE m.lid_row_id = j._id AND p.server = 's.whatsapp.net' ORDER BY m.sort_id DESC LIMIT 1)
         ELSE NULL END AS phone,
       j.server AS server
FROM jid j;
CREATE INDEX idx_jc ON jid_canon(jid_row_id);

-- rows that represent the account owner (never a real participant)
CREATE TABLE me_jids AS
SELECT _id FROM jid WHERE server IN ('lid_me','status_me') OR (user='0' AND server='s.whatsapp.net');

DROP VIEW IF EXISTS chat_view;
CREATE TABLE chat_view AS
SELECT c._id AS _id,
       r.canon AS raw_string_jid,
       r.phone AS phone_jid,
       CASE WHEN r.server='g.us' THEN COALESCE(NULLIF(c.subject,''),'Group') ELSE NULL END AS subject,
       NULLIF(COALESCE(c.archived,0),0) AS archived,
       COALESCE(c.created_timestamp, c.sort_timestamp, 0) AS created_timestamp,
       r.server AS server
FROM chat c JOIN jid_canon r ON r.jid_row_id=c.jid_row_id
WHERE r.server IN ('s.whatsapp.net','g.us','lid')
  AND r.canon <> '0@s.whatsapp.net'
  AND COALESCE(c.last_message_row_id,0) > 0;
CREATE INDEX idx_cv ON chat_view(_id);
CREATE INDEX idx_cv_jid ON chat_view(raw_string_jid);

-- Android message_type -> legacy media_wa_type. status=6 means "do not import" (watoi skips it).
CREATE TABLE messages AS
SELECT m._id AS _id,
       cv.raw_string_jid AS key_remote_jid,
       m.from_me AS key_from_me,
       m.key_id AS key_id,
       CASE WHEN m.message_type IN (7,90,10,99) THEN 6
            WHEN m.text_data IS NULL AND m.message_type NOT IN (0,1,2,3,4,5,9,13,14,15,16,20,42,43,66,109,92) THEN 6
            ELSE 0 END AS status,
       m.timestamp AS timestamp,
       CASE m.message_type
            WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 4 WHEN 5 THEN 5
            WHEN 9 THEN 9 WHEN 13 THEN 13 WHEN 14 THEN 14 WHEN 15 THEN 15 WHEN 16 THEN 16
            WHEN 20 THEN 20 WHEN 42 THEN 1 WHEN 43 THEN 3
            ELSE 0 END AS media_wa_type,
       CASE WHEN m.message_type IN (66,109) THEN 'POLL: ' || COALESCE(m.text_data,'')
            WHEN m.message_type = 92 THEN 'EVENT: ' || COALESCE(ev.name,'') || COALESCE(' - ' || ev.description, '')
            ELSE m.text_data END AS data,
       COALESCE(NULLIF(mm.media_caption,''),
                CASE WHEN m.message_type IN (1,3,9,13,42,43) THEN NULLIF(m.text_data,'') END) AS media_caption,
       CASE WHEN m.from_me=0 THEN sr.canon END AS remote_resource,
       m.message_type AS orig_type
FROM message m
JOIN chat_view cv ON cv._id=m.chat_row_id
LEFT JOIN message_media mm ON mm.message_row_id=m._id
LEFT JOIN message_event ev ON ev.message_row_id=m._id
LEFT JOIN jid_canon sr ON sr.jid_row_id=m.sender_jid_row_id;
CREATE INDEX idx_msgs ON messages(key_remote_jid, status, timestamp);
CREATE INDEX idx_msgs_key ON messages(key_remote_jid, key_id);

DELETE FROM chat_view WHERE NOT EXISTS (SELECT 1 FROM messages ms WHERE ms.key_remote_jid=chat_view.raw_string_jid AND ms.status<>6);

DROP TABLE IF EXISTS group_participants;
CREATE TABLE group_participants AS
SELECT cv.raw_string_jid AS gjid,
       r.canon AS jid,
       r.phone AS phone_jid,
       CASE WHEN COALESCE(gp.rank,0)>0 THEN 1 ELSE 0 END AS admin
FROM group_participant_user gp
JOIN chat c ON c.jid_row_id=gp.group_jid_row_id
JOIN chat_view cv ON cv._id=c._id
JOIN jid_canon r ON r.jid_row_id=gp.user_jid_row_id
WHERE gp.user_jid_row_id NOT IN (SELECT _id FROM me_jids) AND cv.subject IS NOT NULL;
CREATE INDEX idx_gp ON group_participants(gjid);

-- every person's canonical id -> phone id (for ZCONTACTIDENTIFIER / readable fallback names)
CREATE TABLE canon_phone AS
SELECT canon, MAX(phone) AS phone FROM jid_canon
WHERE canon LIKE '%@lid' AND phone IS NOT NULL GROUP BY canon;
CREATE UNIQUE INDEX idx_cp ON canon_phone(canon);

CREATE TABLE starred_keys AS
SELECT ms.key_remote_jid AS jid, ms.key_id AS key_id
FROM messages ms JOIN message am ON am._id=ms._id WHERE am.starred=1 AND ms.status<>6;
