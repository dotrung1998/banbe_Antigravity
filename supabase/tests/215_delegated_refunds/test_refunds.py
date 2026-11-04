#!/usr/bin/env python3
"""
Migration 215 (delegated refunds, note 76 phase 9c) against the THROWAWAY stack (g-db), on the 210 seed.
Each check runs as a real `authenticated` caller inside its own rolled-back transaction. Touches nothing remote.
Exit 0 only if every check holds.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = os.path.join(ROOT, 'supabase/migrations/20261231000215_215_delegated_refunds.sql')
M128 = os.path.join(ROOT, 'supabase/migrations/20261108000128_128_refund_proof.sql')
M211 = os.path.join(ROOT, 'supabase/migrations/20261231000211_211_event_project_jobs.sql')
ROLLBACK = os.path.join(ROOT, 'supabase/rollbacks/20261231000215_215_revert_delegated_refunds.sql')
FAILS, PASSES = [], 0


def check(name, cond, detail=''):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS.append(name)
        print(f'  FAIL {name} {detail}')


def uid(n):
    return f'a{n:02x}00000-0000-0000-0000-0000000000{n:02x}'


OWNER, SECOND, MGR, FIN, LEAD, HELP, HM, HC, RF, OUT = (uid(i) for i in range(1, 11))
B1, B2, B3, B4, B5, B6 = ('7f000000-0000-0000-0000-00000000000' + c for c in '123456')
C1, C2, C3, C4, C5, C6 = ('7c000000-0000-0000-0000-00000000000' + c for c in '123456')
DEST = '7d000000-0000-0000-0000-000000000001'
THREAD = '7b000000-0000-0000-0000-000000000001'
SNAP = '{"bank_name": "VCB", "account_number": "0123456789", "account_holder_name": "PJ OUT"}'
# C1 owed (pj_main, ready), C2 owed with no refund account, C3 disputed on the read-only pj_past with an open dispute,
# C4 owed on pj_past (no dispute), C5 already confirmed by the guest, C6 owed (pj_main, second guest, ready).
SEED = f"""
INSERT INTO refund_destinations (id, user_id, bank_name, account_number, account_holder_name) VALUES
  ('{DEST}', '{OUT}', 'VCB', '0123456789', 'PJ OUT');
INSERT INTO bookings (id, event_id, user_id, qty, total_vnd, status, payment_state, payment_ref) VALUES
  ('{B1}', 'pj_main', '{OUT}', 2, 980000, 'cancelled', 'confirmed', 'BR1'),
  ('{B2}', 'pj_main', '{HELP}', 1, 490000, 'cancelled', 'confirmed', 'BR2'),
  ('{B3}', 'pj_past', '{OUT}', 1, 490000, 'cancelled', 'confirmed', 'BR3'),
  ('{B4}', 'pj_past', '{OUT}', 1, 490000, 'cancelled', 'confirmed', 'BR4'),
  ('{B5}', 'pj_main', '{OUT}', 1, 490000, 'cancelled', 'confirmed', 'BR5'),
  ('{B6}', 'pj_main', '{OUT}', 1, 490000, 'cancelled', 'confirmed', 'BR6');
ALTER TABLE refund_claims DISABLE TRIGGER USER;
INSERT INTO refund_claims (id, booking_id, amount_vnd, reason, status, selected_destination_id, recipient_snapshot, refund_due_at) VALUES
  ('{C1}', '{B1}', 980000, 'host_cancelled', 'owed', '{DEST}', '{SNAP}', now() + interval '3 days'),
  ('{C2}', '{B2}', 490000, 'host_cancelled', 'owed', NULL, NULL, now() + interval '3 days'),
  ('{C3}', '{B3}', 490000, 'host_cancelled', 'disputed', '{DEST}', '{SNAP}', now() - interval '30 days'),
  ('{C4}', '{B4}', 490000, 'host_cancelled', 'owed', '{DEST}', '{SNAP}', now() - interval '30 days'),
  ('{C5}', '{B5}', 490000, 'host_cancelled', 'guest_confirmed', '{DEST}', '{SNAP}', now() - interval '1 day'),
  ('{C6}', '{B6}', 490000, 'host_cancelled', 'owed', '{DEST}', '{SNAP}', now() + interval '2 days');
ALTER TABLE refund_claims ENABLE TRIGGER USER;
INSERT INTO dispute_threads (id, event_id, booking_id, refund_claim_id, guest_id, organizer_id, kind, created_at)
VALUES ('{THREAD}', 'pj_past', '{B3}', '{C3}', '{OUT}', 'org_pj', 'refund', now() - interval '2 days');
"""


def flags(on):
    keys = ['event_project_hub', 'project_delegate_payments', 'project_delegate_checkin', 'project_delegate_refunds']
    return ''.join(f"UPDATE app_feature_flags SET enabled = {str(k in on).lower()} WHERE key = '{k}';\n" for k in keys)


ON = flags({'event_project_hub', 'project_delegate_refunds'})
ALONE = ON + "UPDATE event_projects SET refund_approval = 'finance_alone' WHERE event_id IN ('pj_main', 'pj_past');\n"


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(u):
    if u == 'admin':
        return 'RESET ROLE;\n'
    return f"SELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': u, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


LAST_ERR = ['']


def tx(steps, setup=''):
    body = 'BEGIN;\n' + SEED + setup
    for i, (u, expr) in enumerate(steps):
        if expr.startswith('!'):
            body += as_user(u) + expr[1:].rstrip(';') + f";\nSELECT 'R|{i}|done';\n"
        else:
            body += as_user(u) + f"SELECT 'R|{i}|' || coalesce(({expr})::text, 'NULL');\n"
    body += 'ROLLBACK;\n'
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=0'],
                       input=body, capture_output=True, text=True)
    res = {}
    for line in r.stdout.splitlines():
        m = re.match(r'R\|(\d+)\|(.*)$', line)
        if m:
            res[int(m.group(1))] = m.group(2)
    LAST_ERR[0] = r.stderr
    if 'ERROR' in r.stderr and 'row-level security' not in r.stderr:
        print('  sql error:', r.stderr.strip()[:300])
    return res


def j(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


VIEW = "public.get_event_refund_view('{e}')::text"
REQ = "public.request_refund_send('{c}', 'Sent from the team account', {p})::text"
MARK = "public.mark_refund_sent('{c}', 'sent', NULL)::text"
APPROVE = "public.approve_refund_send('{c}')::text"
DECLINE = "public.decline_refund_send('{c}', {r})::text"
MODE = "public.project_set_refund_approval('{e}', '{m}')::text"
GRANT = "public.project_extend_dispute_grant('{e}', '{u}', '{c}', now() + interval '{d}')::text"
AUDIT = "(SELECT count(*) FROM event_money_audit WHERE action = '{a}' AND refund_claim_id = '{c}' AND actor_id = '{u}')"
STATUS = "(SELECT status::text FROM refund_claims WHERE id = '{c}')"
REQSTATUS = "(SELECT string_agg(status, ',' ORDER BY created_at) FROM event_refund_send_requests WHERE refund_claim_id = '{c}')"
NOTES = "(SELECT count(*) FROM notifications WHERE kind = '{k}' AND recipient_id = '{u}')"
UPLOAD = "!INSERT INTO storage.objects (bucket_id, name) VALUES ('refund-proof', '{c}/receipt.jpg')"


def req(c, p='NULL'):
    return REQ.format(c=c, p=p)


print('215: switch off — nothing changes')
r = tx([(FIN, req(C1)), (FIN, VIEW.format(e='pj_main')), (FIN, MARK.format(c=C1)), (OWNER, MARK.format(c=C1))], flags({'event_project_hub', 'project_delegate_payments'}))
check('Finance cannot record a refund while the switch is off', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('no refund list for Finance while off', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))
check('Finance cannot mark a refund sent while off', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
check('the owner marks a refund sent as before', j(r.get(3)).get('success') is True, r.get(3))
r = tx([(SECOND, MARK.format(c=C1)), ('admin', "(SELECT count(*) FROM event_money_audit)")], flags(set()))
check('the second organizer account marks sent as before (hub off), no audit row', j(r.get(0)).get('success') is True and r.get(1) == '0', r)

print('215: who may')
for who, name, want in [(FIN, 'Finance', True), (HM, 'helper with money access', True), (HC, 'helper with check-in only', False),
                        (HELP, 'helper', False), (MGR, 'manager without access', False), (OUT, 'outsider (the guest)', False), (RF, 'removed Finance', False)]:
    r = tx([(who, VIEW.format(e='pj_main')), (who, req(C1))], ON)
    check(f'refund list: {name}', (j(r.get(0)).get('success') is True) == want, r.get(0))
    check(f'record a refund: {name}', (j(r.get(1)).get('success') is True) == want, r.get(1))
r = tx([(FIN, VIEW.format(e='pj_main')), (OWNER, VIEW.format(e='pj_main'))], ON)
v = j(r.get(0))
check('the list shows the open claims on this event only', sorted(c['claim_id'] for c in v.get('claims', [])) == sorted([C1, C2, C6]), v)
c1 = next((c for c in v.get('claims', []) if c['claim_id'] == C1), {})
check('with amount and the refund account needed to send', c1.get('amount') == 980000 and (c1.get('account') or {}).get('account_number') == '0123456789', c1)
check('a claim with no refund account shows none', next((c for c in v['claims'] if c['claim_id'] == C2), {}).get('account') is None, v)
check('the list never carries a proof path, a note or a document', not re.search(r'proof_path|receipt|invoice|"note"|refund-proof|pay-proof', r.get(0) or ''), r.get(0))
check('the mode is host by default; Finance is not the Host', v.get('mode') == 'host' and v.get('host') is False, v)
check('the Host sees the same list as Host', j(r.get(1)).get('host') is True and len(j(r.get(1)).get('claims', [])) == 3, r.get(1))

print('215: Host approval (default)')
r = tx([(FIN, MARK.format(c=C1)), ('admin', STATUS.format(c=C1))], ON)
check('Finance marking sent directly is refused with APPROVAL_REQUIRED', j(r.get(0)).get('error') == 'APPROVAL_REQUIRED', r.get(0))
check('the claim stays owed', r.get(1) == 'owed', r.get(1))
r = tx([(FIN, req(C1, f"'{C1}/receipt.jpg'")), ('admin', AUDIT.format(a='refund_request', c=C1, u=FIN)), ('admin', STATUS.format(c=C1)),
        ('admin', NOTES.format(k='project_refund_request', u=OWNER)), ('admin', NOTES.format(k='project_refund_request', u=SECOND)),
        ('admin', NOTES.format(k='refund_marked_sent', u=OUT)), (FIN, req(C1)), (FIN, VIEW.format(e='pj_main')), (HM, req(C1))], ON)
check('Finance records a transfer', j(r.get(0)).get('success') is True and j(r.get(0)).get('status') == 'pending', r.get(0))
check('one audit row', r.get(1) == '1', r.get(1))
check('the claim is still owed (the guest is told nothing yet)', r.get(2) == 'owed' and r.get(5) == '0', r)
check('both organizer accounts are asked to approve', r.get(3) == '1' and r.get(4) == '1', r)
check('a second record for the same claim is refused', j(r.get(6)).get('error') == 'ALREADY_REQUESTED' and j(r.get(8)).get('error') == 'ALREADY_REQUESTED', r)
rq = next((c for c in j(r.get(7)).get('claims', []) if c['claim_id'] == C1), {}).get('request') or {}
check('the list shows the waiting record as mine, with its receipt flag', rq.get('mine') is True and rq.get('has_proof') is True, rq)

r = tx([(FIN, '!SELECT ' + req(C1, f"'{C1}/receipt.jpg'")), (FIN, APPROVE.format(c=C1)), (MGR, APPROVE.format(c=C1)), (OWNER, APPROVE.format(c=C1)),
        ('admin', STATUS.format(c=C1)), ('admin', REQSTATUS.format(c=C1)), ('admin', AUDIT.format(a='refund_approve', c=C1, u=OWNER)),
        ('admin', NOTES.format(k='refund_marked_sent', u=OUT)), ('admin', f"(SELECT proof_path || '|' || note FROM refund_claims WHERE id = '{C1}')"),
        ('admin', "(SELECT count(*) FROM event_money_audit WHERE action = 'refund_mark_sent')")], ON)
check('Finance cannot approve its own record', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))
check('nor can a Manager', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
check('the Host approves', j(r.get(3)).get('success') is True and j(r.get(3)).get('status') == 'host_marked_sent', r.get(3))
check('the claim is marked sent and the record approved', r.get(4) == 'host_marked_sent' and r.get(5) == 'approved', r)
check('one approve audit row; the Host\'s mark is not a delegate mark', r.get(6) == '1' and r.get(9) == '0', r)
check('the guest is told once, with the team\'s receipt and note', r.get(7) == '1' and (r.get(8) or '').startswith(f'{C1}/receipt.jpg|') and 'Sent from the team account' in (r.get(8) or ''), r)
r = tx([(OWNER, APPROVE.format(c=C1))], ON)
check('approving with nothing waiting says so', j(r.get(0)).get('error') == 'NO_REQUEST', r.get(0))
r = tx([(FIN, '!SELECT ' + req(C1)), ('admin', f"!UPDATE event_project_members SET grant_expires_at = now() - interval '1 minute' WHERE user_id = '{FIN}' AND event_id = 'pj_main'"),
        (OWNER, APPROVE.format(c=C1))], ON)
check('a record made before the grant ended stays approvable by the Host', j(r.get(2)).get('success') is True, r.get(2))

r = tx([(FIN, '!SELECT ' + req(C1)), (OWNER, DECLINE.format(c=C1, r="''")), (FIN, DECLINE.format(c=C1, r="'Wrong account'")),
        (OWNER, DECLINE.format(c=C1, r="'Wrong account number'")), ('admin', REQSTATUS.format(c=C1)), ('admin', STATUS.format(c=C1)),
        ('admin', AUDIT.format(a='refund_decline', c=C1, u=OWNER)), ('admin', NOTES.format(k='project_refund_declined', u=FIN)),
        (FIN, VIEW.format(e='pj_main')), (FIN, req(C1))], ON)
check('declining needs a reason', j(r.get(1)).get('error') == 'REASON_REQUIRED', r.get(1))
check('Finance cannot decline', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
check('the Host declines with a reason; the claim stays owed', j(r.get(3)).get('success') is True and r.get(4) == 'declined' and r.get(5) == 'owed', r)
check('one decline audit row and the person who recorded it is told', r.get(6) == '1' and r.get(7) == '1', r)
ld = next((c for c in j(r.get(8)).get('claims', []) if c['claim_id'] == C1), {}).get('last_declined') or {}
check('Finance sees the reason, and may record again', ld.get('reason') == 'Wrong account number' and j(r.get(9)).get('success') is True, r)
r = tx([(FIN, '!SELECT ' + req(C1)), (OWNER, MARK.format(c=C1)), ('admin', REQSTATUS.format(c=C1))], ON)
check('the Host marking sent directly closes a waiting record', j(r.get(1)).get('success') is True and r.get(2) == 'closed', r)

print('215: bad records')
r = tx([(FIN, req(C1, f"'{C6}/receipt.jpg'")), (FIN, req(C2)), (FIN, req(C5)), (FIN, req(C3))], ON)
check('a receipt outside the claim\'s folder is refused', j(r.get(0)).get('error') == 'INVALID_PROOF_PATH', r.get(0))
check('no refund account, no record', j(r.get(1)).get('error') == 'REFUND_DESTINATION_REQUIRED', r.get(1))
check('a settled claim cannot be recorded', j(r.get(2)).get('error') == 'INVALID_STATE', r.get(2))
check('a claim on a read-only project needs a dispute grant', j(r.get(3)).get('error') == 'NOT_AUTHORIZED', r.get(3))

print('215: Finance can refund alone (only the Host switches it)')
r = tx([(FIN, MODE.format(e='pj_main', m='finance_alone')), (MGR, MODE.format(e='pj_main', m='finance_alone')), (OWNER, MODE.format(e='pj_main', m='anyone')),
        (OWNER, MODE.format(e='pj_main', m='finance_alone')), (OWNER, MODE.format(e='pj_main', m='finance_alone')),
        ('admin', "(SELECT count(*) FROM event_money_audit WHERE action = 'set_refund_approval' AND reason = 'finance_alone')"),
        (FIN, MARK.format(c=C1)), ('admin', AUDIT.format(a='refund_mark_sent', c=C1, u=FIN)), ('admin', NOTES.format(k='refund_marked_sent', u=OUT)),
        (HC, MARK.format(c=C6)), (SECOND, MODE.format(e='pj_main', m='host')), (FIN, MARK.format(c=C6))], ON)
check('Finance cannot switch the mode', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('nor can a Manager', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))
check('an unknown mode is refused', j(r.get(2)).get('error') == 'INVALID_VALUE', r.get(2))
check('the Host switches; switching to the same mode again is a no-op with no extra audit row',
      j(r.get(3)).get('success') is True and j(r.get(4)).get('noop') is True and r.get(5) == '1', r)
check('then Finance marks sent directly, audited, and the guest is told', j(r.get(6)).get('success') is True and r.get(7) == '1' and r.get(8) == '1', r)
check('a check-in-only helper still cannot', j(r.get(9)).get('error') == 'NOT_AUTHORIZED', r.get(9))
check('switching back to Host approval stops it again', j(r.get(10)).get('success') is True and j(r.get(11)).get('error') == 'APPROVAL_REQUIRED', r)

print('215: limits on a delegate')
r = tx([(FIN, req(C1)), (OWNER, MARK.format(c=C1))],
       ON + f"UPDATE event_project_members SET grant_expires_at = now() - interval '1 minute' WHERE user_id = '{FIN}' AND event_id = 'pj_main';")
check('an expired grant is refused', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('the Host still marks sent', j(r.get(1)).get('success') is True, r.get(1))
for name, fl in [('the refunds switch alone (hub off)', flags({'project_delegate_refunds'})),
                 ('the payments switch', flags({'event_project_hub', 'project_delegate_payments'})),
                 ('the check-in switch', flags({'event_project_hub', 'project_delegate_checkin'}))]:
    r = tx([(FIN, req(C1))], fl)
    check(f'{name} does not open refunds', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
r = tx([(FIN, req(C1)), (FIN, f"public.get_event_checkin_names('pj_main')::text")], ON + flags({'event_project_hub', 'project_delegate_refunds', 'project_delegate_checkin'}) + "UPDATE events SET status = 'cancelled' WHERE id = 'pj_main';")
check('a cancelled event still lets Finance handle its refunds', j(r.get(0)).get('success') is True, r.get(0))
check('(while check-in on a cancelled event stays closed)', j(r.get(1)).get('success') is not True, r.get(1))
r = tx([(FIN, req(C1))], ON + "ALTER TABLE events DISABLE TRIGGER USER; UPDATE events SET status = 'removed' WHERE id = 'pj_main'; ALTER TABLE events ENABLE TRIGGER USER;")
check('a removed event gives no delegate rights', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))

print('215: dispute grants (M5)')
G = GRANT.format(e='pj_past', u=FIN, c=C3, d='10 days')
r = tx([(FIN, G), (MGR, G), (SECOND, GRANT.format(e='pj_past', u=FIN, c=C3, d='31 days')), (SECOND, GRANT.format(e='pj_past', u=FIN, c=C4, d='5 days')),
        (SECOND, GRANT.format(e='pj_past', u=HELP, c=C3, d='5 days')), (SECOND, GRANT.format(e='pj_past', u=RF, c=C3, d='5 days')),
        (SECOND, GRANT.format(e='pj_main', u=FIN, c=C3, d='5 days')), (SECOND, G), ('admin', AUDIT.format(a='extend_dispute_grant', c=C3, u=SECOND))], ON)
check('Finance cannot grant itself', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('nor can a Manager', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))
check('more than 30 days is refused', j(r.get(2)).get('error') == 'INVALID_VALUE', r.get(2))
check('a claim without an open dispute is refused', j(r.get(3)).get('error') == 'NO_OPEN_DISPUTE', r.get(3))
check('only a money delegate can receive one', j(r.get(4)).get('error') == 'NOT_A_DELEGATE' and j(r.get(5)).get('error') == 'NOT_A_DELEGATE', r)
check('the claim must belong to the event', j(r.get(6)).get('error') == 'NOT_FOUND', r.get(6))
check('the Host grants it (beyond the read-only date), audited', j(r.get(7)).get('success') is True and r.get(8) == '1', r)
r = tx([(SECOND, '!SELECT ' + G), (FIN, VIEW.format(e='pj_past')), (FIN, req(C3)), (FIN, req(C4)), (FIN, MARK.format(c=C3)),
        (FIN, "public.get_event_checkin_names('pj_past')::text"), (FIN, f"public.get_event_money_view('pj_past')::text")],
       ON + flags({'event_project_hub', 'project_delegate_refunds', 'project_delegate_checkin', 'project_delegate_payments'}))
check('the list then shows that one claim only', [c['claim_id'] for c in j(r.get(1)).get('claims', [])] == [C3], r.get(1))
check('Finance may record that refund', j(r.get(2)).get('success') is True, r.get(2))
check('but no other claim on that event', j(r.get(3)).get('error') == 'NOT_AUTHORIZED', r.get(3))
check('under Host approval it still needs the Host', j(r.get(4)).get('error') == 'APPROVAL_REQUIRED', r.get(4))
check('the grant opens neither check-in nor payments', j(r.get(5)).get('success') is not True and j(r.get(6)).get('success') is not True, r)
r = tx([(SECOND, '!SELECT ' + G), (FIN, MARK.format(c=C3)), ('admin', AUDIT.format(a='refund_mark_sent', c=C3, u=FIN))], ALONE)
check('under "Finance alone" the grant holder marks it sent, audited', j(r.get(1)).get('success') is True and r.get(2) == '1', r)
r = tx([(SECOND, '!SELECT ' + G), ('admin', f"!UPDATE dispute_threads SET resolved_at = now() WHERE id = '{THREAD}'"), (FIN, req(C3))], ON)
check('the grant dies the moment the dispute is resolved', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
r = tx([(SECOND, '!SELECT ' + G), ('admin', "!UPDATE event_dispute_refund_grants SET until = now() - interval '1 minute'"), (FIN, req(C3))], ON)
check('an expired dispute grant is refused', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
r = tx([(SECOND, '!SELECT ' + G), ('admin', f"!UPDATE event_project_members SET status = 'removed' WHERE user_id = '{FIN}' AND event_id = 'pj_past'"), (FIN, req(C3))], ON)
check('removing the person from the team ends the grant', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
r = tx([(SECOND, '!SELECT ' + G), ('admin', "!DELETE FROM event_projects WHERE event_id = 'pj_past'"), (FIN, req(C3)),
        (SECOND, '!SELECT public.decline_refund_send(\'' + C3 + '\', \'Not yet\')'), (SECOND, GRANT.format(e='pj_past', u=FIN, c=C3, d='20 days')),
        (SECOND, GRANT.format(e='pj_past', u=HM, c=C3, d='5 days'))], ON)
check('the grant outlives the project purge', j(r.get(2)).get('success') is True, r.get(2))
check('and can be renewed after it, for the same person only', j(r.get(4)).get('success') is True and j(r.get(5)).get('error') == 'NOT_A_DELEGATE', r)
r = tx([(SECOND, '!SELECT ' + G), (FIN, req(C3))], flags({'event_project_hub'}))
check('switching refunds off ends every dispute grant', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))

print('215: transfer receipts')
r = tx([(FIN, UPLOAD.format(c=C1)), ('admin', f"(SELECT count(*) FROM storage.objects WHERE bucket_id = 'refund-proof' AND name = '{C1}/receipt.jpg')")], ON)
check('Finance may upload a receipt into the claim\'s own folder', r.get(1) == '1', r)
for who, c, name in [(HC, C1, 'a check-in-only helper'), (FIN, C5, 'a settled claim'), (FIN, C4, 'a claim on a read-only project'), (OUT, C1, 'the guest')]:
    r = tx([(who, UPLOAD.format(c=c))], ON)
    check(f'no upload: {name}', r.get(0) is None and 'row-level security' in LAST_ERR[0], LAST_ERR[0][-200:])
r = tx([(FIN, UPLOAD.format(c=C1))], flags({'event_project_hub', 'project_delegate_payments'}))
check('no upload while the refunds switch is off', r.get(0) is None, r)
r = tx([(FIN, f"(SELECT count(*) FROM storage.objects WHERE bucket_id = 'refund-proof')")],
       ON + f"INSERT INTO storage.objects (bucket_id, name) VALUES ('refund-proof', '{C1}/host.jpg');")
check('Finance cannot read refund receipts (refund_proof_read is unchanged)', r.get(0) == '0', r.get(0))

print('215: "team access ended" notice')
EXPIRE = "UPDATE event_project_members SET grant_expires_at = now() - interval '1 hour' WHERE event_id = 'pj_main';\n"
PURGE = "!SELECT public.purge_project_data(now())"
GONE = "(SELECT count(*) || '|' || coalesce(max(body), '') FROM notifications WHERE kind = 'project_grants_expired' AND recipient_id = '{u}' AND data->>'event_id' = 'pj_main')"
r = tx([('admin', PURGE), ('admin', GONE.format(u=OWNER)), ('admin', GONE.format(u=SECOND)), ('admin', PURGE), ('admin', GONE.format(u=OWNER)),
        ('admin', "(SELECT grants_expired_notified_at IS NOT NULL FROM event_projects WHERE event_id = 'pj_main')")], ON + EXPIRE)
check('both organizer accounts are told how many refunds are back with them',
      (r.get(1) or '').startswith('1|') and '3 khoản hoàn tiền' in (r.get(1) or '') and (r.get(2) or '').startswith('1|'), r)
check('once only', (r.get(4) or '').startswith('1|') and r.get(5) == 'true', r)
r = tx([('admin', PURGE), ('admin', GONE.format(u=OWNER))], ON)
check('not while a money grant is still live', (r.get(1) or '').startswith('0|'), r)
r = tx([('admin', PURGE), ('admin', GONE.format(u=OWNER))], flags({'event_project_hub', 'project_delegate_payments'}) + EXPIRE)
check('not while refund delegation is off', (r.get(1) or '').startswith('0|'), r)
r = tx([('admin', PURGE), ('admin', GONE.format(u=OWNER)), ('admin', "(SELECT grants_expired_notified_at IS NULL FROM event_projects WHERE event_id = 'pj_main')")],
       ON + EXPIRE + "UPDATE refund_claims SET status = 'guest_confirmed' WHERE id IN ('" + "','".join([C1, C2, C6]) + "');")
r2 = tx([('admin', PURGE), ('admin', "(SELECT count(*) FROM notifications WHERE kind = 'project_grants_expired' AND data->>'event_id' = 'pj_past')")], ON)
check('the long-past event (grants over, refunds open) gets its own notice', r2.get(1) == '2', r2)
check('silent with nothing open, and still armed for a later claim', (r.get(1) or '').startswith('0|') and r.get(2) == 'true', r)

print('215: originals copied verbatim, grants, re-apply, rollback')
def fn(text, name):
    i = text.index(f'CREATE OR REPLACE FUNCTION public.{name}(')
    return [l.strip() for l in text[i:text.index('$$;', i)].splitlines() if l.strip()]
mig = open(MIG).read()
for name, src in [('mark_refund_sent', M128), ('purge_project_data', M211)]:
    old, new = fn(open(src).read(), name), fn(mig, name)
    k = 0
    for line in new:
        if k < len(old) and line == old[k]:
            k += 1
    check(f'every line of the previous {name} survives, in order (only additions)', k == len(old), old[k] if k < len(old) else '')
for name in ['mark_refund_sent', 'approve_refund_send', 'decline_refund_send', 'request_refund_send', 'get_event_refund_view']:
    check(f'{name} never uses project_is_host (money keeps the organizer check)', 'project_is_host(' not in '\n'.join(fn(mig, name)))
r = tx([('admin', f"has_function_privilege('{role}', 'public.{f}', 'EXECUTE')")
        for role, f in [('anon', 'get_event_refund_view(text)'), ('anon', 'request_refund_send(uuid,text,text)'), ('anon', 'approve_refund_send(uuid)'),
                        ('anon', 'mark_refund_sent(uuid,text,text)'), ('anon', 'project_extend_dispute_grant(text,uuid,uuid,timestamptz)'),
                        ('authenticated', 'project_refund_delegate_ok(uuid)'), ('authenticated', 'project_refund_member_ok(text)'),
                        ('authenticated', 'refund_claim_organizer_ok(uuid)'), ('authenticated', 'purge_project_data(timestamptz)')]]
       + [('admin', f"has_table_privilege('authenticated', 'public.{t}', 'SELECT')") for t in ['event_refund_send_requests', 'event_dispute_refund_grants']])
check('anon gets nothing; helpers and tables stay server-only', r and all(x == 'false' for x in r.values()), r)
r = tx([(FIN, req(C1)), (OWNER, APPROVE.format(c=C1))], ON + mig + '\n' + mig)
check('re-apply: idempotent and still working', j(r.get(0)).get('success') is True and j(r.get(1)).get('success') is True, r)
r = tx([(FIN, MARK.format(c=C1)), (OWNER, MARK.format(c=C6)),
        ('admin', "(SELECT count(*) FROM pg_proc WHERE proname IN ('get_event_refund_view', 'request_refund_send', 'approve_refund_send', 'decline_refund_send', 'project_set_refund_approval', 'project_extend_dispute_grant', 'refund_proof_delegate_ok', 'project_refund_delegate_ok'))"),
        ('admin', "(SELECT count(*) FROM pg_policies WHERE policyname = 'refund_proof_delegate_insert')"),
        ('admin', "(SELECT count(*) FROM information_schema.columns WHERE table_name = 'event_projects' AND column_name = 'grants_expired_notified_at')"),
        ('admin', "!SELECT public.purge_project_data(now())")], ALONE + open(ROLLBACK).read())
check('rollback: delegates refused again (even under finance_alone)', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('rollback: the Host path still works', j(r.get(1)).get('success') is True, r.get(1))
check('rollback: the new functions, the policy and the column are gone', r.get(2) == '0' and r.get(3) == '0' and r.get(4) == '0', r)
check('rollback: the purge job still runs', r.get(5) == 'done', r.get(5))
r = tx([('admin', "public.project_limits() ? 'disputeGrantMaxDays'"), ('admin', "public.project_limits() ? 'proofOpenMinutes'")], open(ROLLBACK).read())
check("rollback: 214's limits are back", r.get(0) == 'false' and r.get(1) == 'true', r)

print(f'215: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
