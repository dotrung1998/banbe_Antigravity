-- LOCAL TEST HARNESS ONLY — never deployed, never run against a real project.
-- Migration 165: rewards ledger, attendance awards/reversals, badges, streak, redemption.
-- Runs after the full chain + 01_seed.sql on the throwaway local postgres; self-contained
-- fixtures (ids prefixed 7r / rw_), rolled back at the end.
\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION pg_temp.ok(c boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'FAIL %', label; END IF; RAISE NOTICE 'PASS %', label; END $$;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub', u::text, true) $$;
CREATE FUNCTION pg_temp.bal(u uuid) RETURNS int LANGUAGE sql AS $$ SELECT public.rewards_balance(u) $$;
CREATE FUNCTION pg_temp.mkuser(u uuid, email text, handle text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id,email,phone,phone_confirmed_at,raw_user_meta_data,confirmed_at)
  VALUES (u,email,'+8490001'||substr(handle,2,4),now(),jsonb_build_object('display_name',handle),now()) ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles (id,display_name,handle,role,phone,phone_verified)
  VALUES (u,handle,handle,'participant','+8490001'||substr(handle,2,4),true) ON CONFLICT (id) DO NOTHING;
  INSERT INTO account_phone_grandfathered(user_id,cohort) VALUES (u,'t') ON CONFLICT DO NOTHING;
END $$;
CREATE FUNCTION pg_temp.mkevent(id text, cat text, st text DEFAULT 'live') RETURNS void LANGUAGE sql AS $$
  INSERT INTO events (id,key,name,organizer_id,status,price_vnd,capacity,starts_at,seats_remaining,cat_key)
  VALUES (id,id,'Event '||id,'test_org_a',st::event_status,0,50,now()+interval '2 days',50,cat) ON CONFLICT (id) DO NOTHING $$;
CREATE FUNCTION pg_temp.mkbook(ev text, u uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE b uuid := gen_random_uuid();
BEGIN
  INSERT INTO bookings (id,event_id,user_id,purchaser_id,qty,total_vnd,code,status,payment_state,paid_marked_at)
  VALUES (b,ev,u,u,1,0,'RW-'||substr(b::text,1,8),'confirmed','confirmed',now());
  RETURN b;
END $$;
CREATE FUNCTION pg_temp.checkin(b uuid, as_uid uuid DEFAULT '7a000002-0000-4000-8000-000000000002') RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.as_user(as_uid); RETURN public.check_in_guest(b,'manual'); END $$;
CREATE FUNCTION pg_temp.undo(b uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.as_user('7a000002-0000-4000-8000-000000000002'); RETURN public.undo_check_in(b,'mistake'); END $$;
CREATE FUNCTION pg_temp.ledger_n(u uuid, k text) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.reward_ledger WHERE user_id=u AND source_key LIKE k $$;

DO $t$
DECLARE
  host  uuid := '7a000002-0000-4000-8000-000000000002';
  ua    uuid := '7e0a0001-0000-4000-8000-000000000001';
  ub    uuid := '7e0a0002-0000-4000-8000-000000000002';
  uteam uuid := '7e0a0003-0000-4000-8000-000000000003';
  urcp  uuid := '7e0a0004-0000-4000-8000-000000000004';
  upur  uuid := '7e0a0005-0000-4000-8000-000000000005';
  uadm  uuid := '7e0a0006-0000-4000-8000-000000000006';
  unew  uuid := '7e0a0007-0000-4000-8000-000000000007';
  ucap  uuid := '7e0a0008-0000-4000-8000-000000000008';
  b uuid; b2 uuid; r jsonb; n int; i int; boundary timestamptz; msg text;
BEGIN
  PERFORM pg_temp.mkuser(ua,'rwa@test.dev','u7ra01');   PERFORM pg_temp.mkuser(ub,'rwb@test.dev','u7rb02');
  PERFORM pg_temp.mkuser(uteam,'rwt@test.dev','u7rt03'); PERFORM pg_temp.mkuser(urcp,'rwr@test.dev','u7rr04');
  PERFORM pg_temp.mkuser(upur,'rwp@test.dev','u7rp05');  PERFORM pg_temp.mkuser(uadm,'rwx@test.dev','u7rx06');
  PERFORM pg_temp.mkuser(unew,'rwn@test.dev','u7rn07');  PERFORM pg_temp.mkuser(ucap,'rwc@test.dev','u7rc08');
  UPDATE profiles SET role='admin' WHERE id = uadm;
  INSERT INTO organizer_members (organizer_id,user_id,status) VALUES ('test_org_a',uteam,'accepted');
  PERFORM pg_temp.mkevent('rw_e1','music');   PERFORM pg_temp.mkevent('rw_e2','supper');
  PERFORM pg_temp.mkevent('rw_e3','gallery'); PERFORM pg_temp.mkevent('rw_e4','fashion');

  -- ===== T1 privileges: no client reads or writes any reward table; no internal helper is callable
  PERFORM pg_temp.as_user(ua);
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_ledger; RESET ROLE; RAISE EXCEPTION 'T1a ledger readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN INSERT INTO public.reward_ledger (user_id,entry_type,amount,source_key,rules_version,reason) VALUES (ua,'award',999,'x',1,'x'); RESET ROLE; RAISE EXCEPTION 'T1b ledger writable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.rewards_add_entry(ua,'award',999,'x',NULL,'x','{}'); RESET ROLE; RAISE EXCEPTION 'T1c helper callable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM count(*) FROM public.reward_attendances; RESET ROLE; RAISE EXCEPTION 'T1d facts readable'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  SET LOCAL ROLE anon;
  BEGIN PERFORM public.get_my_rewards(); RESET ROLE; RAISE EXCEPTION 'T1e anon rpc'; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; END;
  PERFORM pg_temp.ok(true, 'T1 no direct table access, no helper access, no anon');

  -- ===== T2 append-only ledger
  PERFORM public.rewards_add_entry(ua,'award',0,'t2:probe',NULL,'probe','{}');
  BEGIN UPDATE public.reward_ledger SET amount = 5 WHERE user_id=ua AND source_key='t2:probe'; RAISE EXCEPTION 'T2a update allowed';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  BEGIN DELETE FROM public.reward_ledger WHERE user_id=ua AND source_key='t2:probe'; RAISE EXCEPTION 'T2b delete allowed';
  EXCEPTION WHEN restrict_violation THEN NULL; END;
  PERFORM pg_temp.ok(true, 'T2 ledger is append-only');

  -- ===== T3 host-confirmed attendance awards once, idempotently
  b := pg_temp.mkbook('rw_e1', ua);
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 0, 'T3a booking alone earns nothing');
  r := pg_temp.checkin(b);
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T3b check-in ok');
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 20, 'T3c +20 for the first valid attendance');
  PERFORM pg_temp.ok(pg_temp.ledger_n(ua,'attend:rw_e1:%') = 1, 'T3d one attend entry');
  r := pg_temp.checkin(b);
  PERFORM pg_temp.ok(NOT (r->>'success')::boolean AND pg_temp.bal(ua) = 20, 'T3e repeated check-in cannot double award');
  PERFORM public.rewards_sync_booking(b); PERFORM public.rewards_sync_booking(b);
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 20 AND pg_temp.ledger_n(ua,'attend:rw_e1:%') = 1, 'T3f re-sync (retry / second device) is a no-op');
  PERFORM pg_temp.as_user(ua);
  PERFORM pg_temp.ok((SELECT (x->>'earned')::boolean FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='first_outing'), 'T3g First outing earned');
  PERFORM pg_temp.ok((public.get_my_reward_summary()->>'streak')::int = 1 AND (public.get_my_reward_summary()->>'active_today')::boolean, 'T3h attendance counts as an active day');

  -- ===== T4 undo / re-check-in cycles: reversal entries, no double award
  r := pg_temp.undo(b);
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T4a undo ok');
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 0, 'T4b undo reverses the coins');
  PERFORM pg_temp.ok(pg_temp.ledger_n(ua,'reverse:%') = 1, 'T4c a reversal entry exists (nothing edited)');
  PERFORM pg_temp.as_user(ua);
  PERFORM pg_temp.ok(NOT (SELECT (x->>'earned')::boolean FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='first_outing'), 'T4d badge revoked with the attendance');
  r := pg_temp.checkin(b);
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 20, 'T4e re-check-in earns the SAME single award again (net +20)');
  r := pg_temp.undo(b); r := pg_temp.checkin(b); r := pg_temp.undo(b); r := pg_temp.checkin(b);
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 20, 'T4f repeated undo/redo cycles stay net +20');
  SELECT count(*) INTO n FROM public.reward_ledger WHERE user_id=ua AND entry_type='award' AND source_key LIKE 'attend:rw_e1:%';
  PERFORM pg_temp.ok(n = 4, 'T4g each validity cycle has its own unique award key (4 cycles)');

  -- ===== T5 own-event / self / team farming is excluded
  b2 := pg_temp.mkbook('rw_e2', host);
  r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok(pg_temp.bal(host) = 0, 'T5a the event owner earns nothing at their own event');
  b2 := pg_temp.mkbook('rw_e2', uteam);
  r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok(pg_temp.bal(uteam) = 0, 'T5b an accepted team member earns nothing');
  b2 := pg_temp.mkbook('rw_e2', uadm);
  r := pg_temp.checkin(b2, uadm);
  PERFORM pg_temp.ok((r->>'success')::boolean AND pg_temp.bal(uadm) = 0, 'T5c self check-in (admin checking themselves in) earns nothing');
  b2 := pg_temp.mkbook('rw_e2', uadm);
  r := pg_temp.checkin(b2, host);
  PERFORM pg_temp.ok(pg_temp.bal(uadm) = 20, 'T5d the same admin as a normal attendee checked in by the host does earn');

  -- ===== T6 gifted tickets: the actual attendee, never the purchaser
  b2 := pg_temp.mkbook('rw_e3', upur);
  PERFORM pg_temp.as_user(upur);
  r := public.gift_ticket(b2, 'Recipient R', 'rwr@test.dev', '1998-05-20'::date, 'rw-gift-1');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T6a gift created');
  r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T6b host admits the seat before it is claimed');
  PERFORM pg_temp.ok(pg_temp.bal(upur) = 0 AND pg_temp.bal(urcp) = 0, 'T6c UNCLAIMED gift: nobody is credited (limitation, not the purchaser)');
  r := pg_temp.undo(b2);
  PERFORM pg_temp.as_user(urcp);
  r := public.claim_gift_ticket((SELECT claim_code FROM bookings WHERE id=b2));
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T6d recipient claims');
  r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok(pg_temp.bal(urcp) = 20, 'T6e CLAIMED gift: the recipient who attended earns');
  PERFORM pg_temp.ok(pg_temp.bal(upur) = 0, 'T6f the purchaser who did not attend earns nothing');

  -- ===== T7 explorer badge (3 categories) + counts of distinct events
  b2 := pg_temp.mkbook('rw_e2', ua); r := pg_temp.checkin(b2);
  b2 := pg_temp.mkbook('rw_e3', ua); r := pg_temp.checkin(b2);
  PERFORM pg_temp.as_user(ua);
  PERFORM pg_temp.ok((SELECT (x->>'earned')::boolean FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='explorer'), 'T7a Explorer after 3 categories');
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 60, 'T7b 3 distinct events = 60 coins');
  b2 := pg_temp.mkbook('rw_e3', ua); r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok(pg_temp.bal(ua) = 60, 'T7c a second booking of the SAME event does not pay again');

  -- ===== T8 per-seat imported attendee earns; holder rule documented
  PERFORM pg_temp.mkevent('rw_e5','popup');
  b2 := pg_temp.mkbook('rw_e5', ub);
  UPDATE bookings SET qty = 2 WHERE id = b2;
  INSERT INTO booking_attendees (booking_id,event_id,seat_no,name,date_of_birth,ticket_code,claimed_by_user_id)
  VALUES (b2,'rw_e5',1,'Holder B','1990-01-01','RW-S1',NULL), (b2,'rw_e5',2,'Friend Imported','1991-01-01','RW-S2',unew);
  PERFORM pg_temp.as_user(host);
  r := public.check_in_guest((SELECT admission_token FROM booking_attendees WHERE ticket_code='RW-S2'), 'scan');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T8a imported seat scanned');
  PERFORM pg_temp.ok(pg_temp.bal(unew) = 20, 'T8b the account that imported and attended that seat earns');

  -- ===== T9 monthly cap (documented 10 paid events/month) without touching bookings
  FOR i IN 1..10 LOOP
    PERFORM pg_temp.mkevent('rw_c'||i,'music');
    b2 := pg_temp.mkbook('rw_c'||i, ucap); r := pg_temp.checkin(b2);
  END LOOP;
  PERFORM pg_temp.ok(pg_temp.bal(ucap) = 200, 'T9a 10 events pay 200');
  PERFORM pg_temp.mkevent('rw_c11','music');
  b2 := pg_temp.mkbook('rw_c11', ucap); r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok((r->>'success')::boolean AND pg_temp.bal(ucap) = 200, 'T9b the 11th event still checks in but pays 0 (cap)');
  PERFORM pg_temp.ok((SELECT reason FROM public.reward_ledger WHERE user_id=ucap AND source_key='attend:rw_c11:1') = 'attendance_cap', 'T9c the capped award is recorded honestly as 0');
  PERFORM pg_temp.as_user(ucap);
  PERFORM pg_temp.ok((SELECT (x->>'progress')::int FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='community_regular') = 10, 'T9d the cap never reduces badge progress');
  -- undoing a coin-paying award frees a cap slot; undoing the capped (0) one changes nothing
  r := pg_temp.undo((SELECT booking_id FROM check_ins WHERE event_id='rw_c11'));
  PERFORM pg_temp.ok(pg_temp.bal(ucap) = 200, 'T9e reversing a capped award reverses 0');

  -- ===== T10 timezone boundaries (fixed Asia/Ho_Chi_Minh, UTC+7)
  PERFORM pg_temp.ok(public.rewards_local_date('2026-10-07 16:59:59+00') = DATE '2026-10-07', 'T10a 16:59:59Z is still Oct 7 locally');
  PERFORM pg_temp.ok(public.rewards_local_date('2026-10-07 17:00:00+00') = DATE '2026-10-08', 'T10b 17:00:00Z is Oct 8 locally');
  PERFORM pg_temp.ok(public.rewards_local_date('2026-12-31 17:00:00+00') = DATE '2027-01-01', 'T10c year boundary');
  -- monthly cap uses the same calendar: awards stamped just BEFORE the local month start don't count
  boundary := date_trunc('month', now() AT TIME ZONE 'Asia/Ho_Chi_Minh') AT TIME ZONE 'Asia/Ho_Chi_Minh';
  PERFORM pg_temp.mkuser('7e0a0009-0000-4000-8000-000000000009','rwm@test.dev','u7rm09');
  FOR i IN 1..10 LOOP
    INSERT INTO public.reward_ledger (user_id,entry_type,amount,source_key,rules_version,reason,ref,created_at)
    VALUES ('7e0a0009-0000-4000-8000-000000000009','award',20,'attend:old'||i||':1',1,'attendance',jsonb_build_object('event_id','old'||i), boundary - interval '1 second');
  END LOOP;
  PERFORM pg_temp.mkevent('rw_m1','music');
  b2 := pg_temp.mkbook('rw_m1','7e0a0009-0000-4000-8000-000000000009'); r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok((SELECT amount FROM public.reward_ledger WHERE user_id='7e0a0009-0000-4000-8000-000000000009' AND source_key='attend:rw_m1:1') = 20, 'T10d last-month awards (1s before local month start) do not count toward this month');
  FOR i IN 1..10 LOOP
    INSERT INTO public.reward_ledger (user_id,entry_type,amount,source_key,rules_version,reason,ref,created_at)
    VALUES ('7e0a0009-0000-4000-8000-000000000009','award',20,'attend:new'||i||':1',1,'attendance',jsonb_build_object('event_id','new'||i), boundary);
  END LOOP;
  PERFORM pg_temp.mkevent('rw_m2','music');
  b2 := pg_temp.mkbook('rw_m2','7e0a0009-0000-4000-8000-000000000009'); r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok((SELECT amount FROM public.reward_ledger WHERE user_id='7e0a0009-0000-4000-8000-000000000009' AND source_key='attend:rw_m2:1') = 0, 'T10e awards at exactly the local month start DO count (cap reached)');

  -- ===== T11 redemption: transactional, idempotent, insufficient balance, unlocks the charm
  PERFORM pg_temp.as_user(ua);
  r := public.redeem_reward('rwd-lantern');           -- 80, balance 60
  PERFORM pg_temp.ok(r->>'error' = 'INSUFFICIENT_BALANCE' AND pg_temp.bal(ua) = 60, 'T11a insufficient balance is refused, nothing charged');
  r := public.save_my_keychain('{"designId":"rwd-comet","enabled":true}');
  PERFORM pg_temp.ok(r->>'error' = 'DESIGN_LOCKED', 'T11b a locked reward design cannot be selected');
  BEGIN INSERT INTO public.profile_keychains (user_id, design_id) VALUES (ua, 'rwd-comet'); RAISE EXCEPTION 'T11c direct write allowed';
  EXCEPTION WHEN check_violation THEN NULL; END;
  r := public.redeem_reward('rwd-comet');             -- 40
  PERFORM pg_temp.ok((r->>'success')::boolean AND pg_temp.bal(ua) = 20, 'T11d redeem charges exactly once');
  r := public.redeem_reward('rwd-comet');
  PERFORM pg_temp.ok((r->>'already_unlocked')::boolean AND pg_temp.bal(ua) = 20, 'T11e a retry / second device is not charged again');
  r := public.save_my_keychain('{"designId":"rwd-comet","enabled":true}');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T11f the unlocked reward design can be used');
  r := public.save_my_keychain('{"designId":"sky-star"}');
  PERFORM pg_temp.ok((r->>'success')::boolean, 'T11g the free basic charms always remain available');
  r := public.redeem_reward('nope');
  PERFORM pg_temp.ok(r->>'error' = 'ITEM_NOT_FOUND', 'T11h unknown item');
  PERFORM pg_temp.ok((public.get_my_unlocked_cosmetics()->'design_ids') = '["rwd-comet"]'::jsonb, 'T11i unlocked list');

  -- ===== T12 reversal AFTER redemption: balance may go negative, the unlock stays, no penalty
  FOR b2 IN SELECT c.booking_id FROM check_ins c JOIN bookings k ON k.id = c.booking_id
             WHERE k.user_id = ua AND c.event_id IN ('rw_e1','rw_e2','rw_e3') ORDER BY c.event_id LOOP
    r := pg_temp.undo(b2);
  END LOOP;
  PERFORM pg_temp.ok(pg_temp.bal(ua) = -40, 'T12a reversing awards already spent leaves a negative balance (documented)');
  PERFORM pg_temp.as_user(ua);
  PERFORM pg_temp.ok((public.get_my_unlocked_cosmetics()->'design_ids') = '["rwd-comet"]'::jsonb, 'T12b the unlocked cosmetic is never revoked');
  r := public.redeem_reward('rwd-crown');
  PERFORM pg_temp.ok(r->>'error' = 'INSUFFICIENT_BALANCE', 'T12c nothing can be redeemed until the balance is earned back');
  PERFORM pg_temp.ok((public.get_my_rewards()->>'success')::boolean, 'T12d no feature is blocked by a negative balance');

  -- ===== T13 onboarding: once, only when completed with answers, never on skip, no back-fill on edit
  PERFORM pg_temp.as_user(unew);
  r := public.complete_preferences_onboarding(NULL);                    -- skip
  PERFORM pg_temp.ok(pg_temp.ledger_n(unew,'onboarding:%') = 0, 'T13a skipping earns nothing');
  r := public.complete_preferences_onboarding('{"version":1,"interests":["music"]}');
  PERFORM pg_temp.ok(pg_temp.ledger_n(unew,'onboarding:%') = 0, 'T13b completing AFTER an earlier skip does not retro-pay (first transition only)');
  PERFORM pg_temp.mkuser('7e0a000a-0000-4000-8000-00000000000a','rwo@test.dev','u7ro0a');
  PERFORM pg_temp.as_user('7e0a000a-0000-4000-8000-00000000000a');
  r := public.complete_preferences_onboarding('{"version":1,"interests":["music"]}');
  PERFORM pg_temp.ok(pg_temp.bal('7e0a000a-0000-4000-8000-00000000000a') = 10, 'T13c completing with answers pays +10');
  r := public.complete_preferences_onboarding('{"version":1,"interests":["gallery"]}');
  r := public.save_my_event_preferences('{"version":1,"interests":["supper"]}');
  PERFORM pg_temp.ok(pg_temp.bal('7e0a000a-0000-4000-8000-00000000000a') = 10 AND pg_temp.ledger_n('7e0a000a-0000-4000-8000-00000000000a','onboarding:%') = 1, 'T13d editing / repeating never pays again');
  PERFORM pg_temp.ok((SELECT (x->>'earned')::boolean FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='ready_to_explore'), 'T13e Ready to explore earned');

  -- ===== T14 streak: deliberate actions only, once per local date, no penalty for gaps
  PERFORM pg_temp.mkuser('7e0a000b-0000-4000-8000-00000000000b','rws@test.dev','u7rs0b');
  PERFORM pg_temp.as_user('7e0a000b-0000-4000-8000-00000000000b');
  r := public.record_active_day('open', NULL);
  PERFORM pg_temp.ok(r->>'error' = 'UNSUPPORTED_SOURCE', 'T14a an app open is not an active day');
  r := public.record_active_day('save', 'rw_e1');
  PERFORM pg_temp.ok(r->>'error' = 'NOT_VERIFIED', 'T14b claiming a save that does not exist is refused');
  INSERT INTO favorites (user_id,event_id) VALUES ('7e0a000b-0000-4000-8000-00000000000b','rw_e1');
  r := public.record_active_day('save', 'rw_e1');
  PERFORM pg_temp.ok((r->>'success')::boolean AND (r->>'streak')::int = 1, 'T14c a verified save counts');
  r := public.record_active_day('save', 'rw_e1'); r := public.record_active_day('save', 'rw_e1');
  PERFORM pg_temp.ok((SELECT count(*) FROM reward_active_days WHERE user_id='7e0a000b-0000-4000-8000-00000000000b') = 1, 'T14d once per local date no matter how many calls');
  UPDATE favorites SET created_at = NULL WHERE user_id='7e0a000b-0000-4000-8000-00000000000b';
  r := public.record_active_day('save', 'rw_e1');
  PERFORM pg_temp.ok(r->>'error' = 'NOT_VERIFIED', 'T14e a pre-existing (un-stamped) favorite cannot manufacture a day');
  PERFORM pg_temp.ok(pg_temp.bal('7e0a000b-0000-4000-8000-00000000000b') = 0, 'T14f a streak never creates coins');
  -- consecutive days, a gap, and "alive through yesterday"
  DELETE FROM reward_active_days WHERE user_id='7e0a000b-0000-4000-8000-00000000000b';
  INSERT INTO reward_active_days (user_id, local_date, source)
  SELECT '7e0a000b-0000-4000-8000-00000000000b', public.rewards_local_date(now()) - d, 'save' FROM unnest(ARRAY[1,2,3,6,7]) d;
  PERFORM pg_temp.ok((public.rewards_streak_of('7e0a000b-0000-4000-8000-00000000000b')->>'current')::int = 3, 'T14g streak alive through yesterday = 3');
  PERFORM pg_temp.ok((public.rewards_streak_of('7e0a000b-0000-4000-8000-00000000000b')->>'longest')::int = 3, 'T14h longest = 3');
  DELETE FROM reward_active_days WHERE user_id='7e0a000b-0000-4000-8000-00000000000b' AND local_date >= public.rewards_local_date(now()) - 3;
  PERFORM pg_temp.ok((public.rewards_streak_of('7e0a000b-0000-4000-8000-00000000000b')->>'current')::int = 0, 'T14i a missed day resets the count to 0 — with no penalty');
  PERFORM pg_temp.as_user('7e0a000b-0000-4000-8000-00000000000b');
  PERFORM pg_temp.ok((public.get_my_rewards()->>'success')::boolean, 'T14j nothing is blocked after a missed day');

  -- ===== T15 host milestone: 3 ENDED events each with a legitimate non-owner attendee
  FOR i IN 1..4 LOOP PERFORM pg_temp.mkevent('rw_h'||i,'music'); END LOOP;
  b2 := pg_temp.mkbook('rw_h1', ub); r := pg_temp.checkin(b2);
  b2 := pg_temp.mkbook('rw_h2', ub); r := pg_temp.checkin(b2);
  b2 := pg_temp.mkbook('rw_h3', host); r := pg_temp.checkin(b2, host);         -- only the owner "attends"
  UPDATE events SET status='ended' WHERE id IN ('rw_h1','rw_h2','rw_h3');
  PERFORM pg_temp.as_user(host);
  PERFORM pg_temp.ok(NOT (SELECT (x->>'earned')::boolean FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='host_milestone'), 'T15a 2 qualifying events (+1 owner-only event) is not enough');
  PERFORM pg_temp.ok((SELECT (x->>'progress')::int FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='host_milestone') = 2, 'T15b progress counts only events with a legitimate non-owner attendee');
  b2 := pg_temp.mkbook('rw_h4', ub); r := pg_temp.checkin(b2);
  UPDATE events SET status='ended' WHERE id = 'rw_h4';
  PERFORM pg_temp.as_user(host);
  PERFORM pg_temp.ok((SELECT (x->>'earned')::boolean FROM jsonb_array_elements(public.get_my_rewards()->'badges') x WHERE x->>'code'='host_milestone'), 'T15c Host milestone earned from the real lifecycle (status = ended) + real attendees');

  -- ===== T16 cancelling an event invalidates attendance and reverses coins
  PERFORM pg_temp.mkevent('rw_x1','music');
  b2 := pg_temp.mkbook('rw_x1', ub); r := pg_temp.checkin(b2);
  n := pg_temp.bal(ub);
  UPDATE events SET status='cancelled' WHERE id='rw_x1';
  PERFORM pg_temp.ok(pg_temp.bal(ub) = n - 20, 'T16 a cancelled event reverses its award');

  -- ===== T17 owner scoping: another account sees only its own data
  PERFORM pg_temp.as_user(ub);
  PERFORM pg_temp.ok((SELECT count(*) FROM jsonb_array_elements(public.get_my_rewards()->'history') x WHERE x->>'event_name' = 'Event rw_c1') = 0, 'T17a account B never sees account A or C history');
  PERFORM pg_temp.ok((public.get_my_reward_summary()->>'balance')::int = pg_temp.bal(ub), 'T17b summary reads the caller only');

  -- ===== T18 a failure in reward bookkeeping never blocks the check-in
  PERFORM pg_temp.mkevent('rw_f1','music');
  b2 := pg_temp.mkbook('rw_f1', ub);
  ALTER TABLE public.reward_ledger DISABLE TRIGGER reward_ledger_no_update;  -- (irrelevant; keep ledger intact)
  ALTER TABLE public.reward_ledger ENABLE TRIGGER reward_ledger_no_update;
  UPDATE public.reward_rule_versions SET rules = rules || '{"attendance_coins":"oops"}'::jsonb WHERE is_active;
  r := pg_temp.checkin(b2);
  PERFORM pg_temp.ok((r->>'success')::boolean AND EXISTS (SELECT 1 FROM check_ins WHERE booking_id=b2), 'T18 a broken rule never blocks a legitimate check-in');

  RAISE NOTICE 'REWARDS RESULT: ALL PASS';
END
$t$;
ROLLBACK;
