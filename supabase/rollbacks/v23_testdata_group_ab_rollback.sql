-- Rollback for supabase/drafts/v23-testdata/group-ab-revive.sql
-- Restores the exact pre-change event_date, starts_at and status (backup 2026-11-13, ~/banbe-backups/2026-11-13-pre-v23-testdata/events.json).
-- Run: supabase db query --linked -f <this file>
BEGIN;
UPDATE events SET event_date='2026-08-19', starts_at='2026-08-19T23:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='phokhuya' AND key='phokhuya';
UPDATE events SET event_date='2026-08-09', starts_at='2026-08-09T21:30:00+00:00'::timestamptz, status='ended'::event_status WHERE id='modular' AND key='modular';
UPDATE events SET event_date='2026-10-16', starts_at='2026-10-16T20:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='bangcoi' AND key='bangcoi';
UPDATE events SET event_date='2026-09-06', starts_at='2026-09-06T20:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='orbit' AND key='orbit';
UPDATE events SET event_date='2026-09-20', starts_at='2026-09-20T17:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='compound' AND key='compound';
UPDATE events SET event_date='2026-09-20', starts_at='2026-09-20T21:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='jazzgac' AND key='jazzgac';
UPDATE events SET event_date='2026-10-09', starts_at='2026-10-09T15:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='chieucham' AND key='chieucham';
UPDATE events SET event_date='2026-11-05', starts_at='2026-11-05T17:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='khongnguoi' AND key='khongnguoi';
UPDATE events SET event_date='2026-09-23', starts_at='2026-09-23T19:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='fanci' AND key='fanci';
UPDATE events SET event_date='2026-09-28', starts_at='2026-09-28T19:30:00+00:00'::timestamptz, status='ended'::event_status WHERE id='motlop' AND key='motlop';
UPDATE events SET event_date='2026-10-01', starts_at='2026-10-01T19:30:00+00:00'::timestamptz, status='ended'::event_status WHERE id='banrieng' AND key='banrieng';
UPDATE events SET event_date='2026-11-23', starts_at='2026-11-23T15:00:00+00:00'::timestamptz, status='live'::event_status WHERE id='phong302' AND key='phong302';
UPDATE events SET event_date='2026-11-22', starts_at='2026-11-22T19:30:00+00:00'::timestamptz, status='live'::event_status WHERE id='comnha' AND key='comnha';
UPDATE events SET event_date='2026-09-11', starts_at='2026-09-11T18:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='vuonsau' AND key='vuonsau';
UPDATE events SET event_date='2026-10-01', starts_at='2026-10-01T18:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='vungtrang' AND key='vungtrang';
UPDATE events SET event_date='2026-09-04', starts_at='2026-09-04T22:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='pianomuon' AND key='pianomuon';
UPDATE events SET event_date='2026-10-28', starts_at='2026-10-28T19:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='noigiay' AND key='noigiay';
UPDATE events SET event_date='2026-11-04', starts_at='2026-11-04T19:00:00+00:00'::timestamptz, status='ended'::event_status WHERE id='bepnho' AND key='bepnho';
COMMIT;
