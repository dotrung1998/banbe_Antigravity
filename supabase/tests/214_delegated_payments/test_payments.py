#!/usr/bin/env python3
"""
Migration 214 (delegated payment confirmation, note 76 phase 9b) against the THROWAWAY stack (g-db), on the 210 seed.
Each check runs as a real `authenticated` caller inside its own rolled-back transaction. Touches nothing remote.
Exit 0 only if every check holds.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = os.path.join(ROOT, 'supabase/migrations/20261231000214_214_delegated_payments.sql')
M213 = os.path.join(ROOT, 'supabase/migrations/20261231000213_213_remove_auto_payment_confirmation.sql')
M060 = os.path.join(ROOT, 'supabase/migrations/20260921000060_060_confirm_payment_sets_payment_state.sql')
ROLLBACK = os.path.join(ROOT, 'supabase/rollbacks/20261231000214_214_revert_delegated_payments.sql')
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
BW, BH, BC, BP = ('7e000000-0000-0000-0000-00000000000' + c for c in '1234')  # waiting, holding, confirmed, past event
SEED = f"""
INSERT INTO bookings (id, event_id, user_id, qty, total_vnd, status, payment_state, payment_ref, paid_marked_at, proof_path) VALUES
  ('{BW}', 'pj_main', '{OUT}', 2, 980000, 'pending', 'pending_verification', 'BB123', now() - interval '1 hour', '{BW}/transfer.jpg'),
  ('{BH}', 'pj_main', '{HELP}', 1, 490000, 'pending', 'holding', 'BB124', NULL, '{BH}/transfer.jpg'),
  ('{BC}', 'pj_main', '{LEAD}', 1, 490000, 'confirmed', 'confirmed', 'BB125', now() - interval '2 days', '{BC}/transfer.jpg'),
  ('{BP}', 'pj_past', '{OUT}', 1, 490000, 'pending', 'pending_verification', 'BB126', now() - interval '41 days', '{BP}/transfer.jpg');
INSERT INTO storage.objects (bucket_id, name) VALUES
  ('pay-proof', '{BW}/transfer.jpg'), ('pay-proof', '{BH}/transfer.jpg'), ('pay-proof', '{BC}/transfer.jpg'),
  ('payment-documents', '{BW}/invoice.pdf'), ('payment-documents', '{BC}/receipt.pdf');
"""


def flags(on):
    keys = ['event_project_hub', 'project_delegate_payments', 'project_delegate_checkin']
    return ''.join(f"UPDATE app_feature_flags SET enabled = {str(k in on).lower()} WHERE key = '{k}';\n" for k in keys)


ON = flags({'event_project_hub', 'project_delegate_payments'})


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(u):
    if u == 'admin':
        return 'RESET ROLE;\n'
    return f"SELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': u, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


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
    if 'ERROR' in r.stderr:
        print('  sql error:', r.stderr.strip()[:300])
    return res


def j(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


VIEW = "public.get_event_money_view('pj_main')::text"
VERIFY = "public.verify_payment('{b}', 'organizer', 'organizer', '{{}}')::text"
CONFIRM = "public.confirm_payment('{b}', 'bank')::text"
OPEN = "public.open_payment_proof('{b}')::text"
SEE = "(SELECT count(*) FROM storage.objects WHERE bucket_id = '{bucket}' AND name LIKE '{b}/%')"
AUDIT = "(SELECT count(*) FROM event_money_audit WHERE action = '{a}' AND booking_id = '{b}' AND actor_id = '{u}')"

print('214: switch off — nothing changes')
r = tx([(OWNER, VERIFY.format(b=BW)), (FIN, VERIFY.format(b=BW)), (FIN, VIEW), (FIN, OPEN.format(b=BW))], flags({'event_project_hub'}))
check('the owner confirms as before', j(r.get(0)).get('success') is True, r.get(0))
check('Finance is refused while the switch is off', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))
check('no money view for Finance while off', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
check('no proof for Finance while off', j(r.get(3)).get('error') == 'NOT_AUTHORIZED', r.get(3))
r = tx([(SECOND, CONFIRM.format(b=BW))], flags(set()))
check('the second organizer account confirms as before (hub off)', j(r.get(0)).get('success') is True, r.get(0))

print('214: who may')
for who, name, want in [(FIN, 'Finance', True), (HM, 'helper with money access', True), (HC, 'helper with check-in only', False),
                        (HELP, 'helper', False), (MGR, 'manager without access', False), (OUT, 'outsider (the guest)', False), (RF, 'removed Finance', False)]:
    r = tx([(who, VIEW), (who, VERIFY.format(b=BW))], ON)
    check(f'money view: {name}', (j(r.get(0)).get('success') is True) == want, r.get(0))
    check(f'confirm: {name}', (j(r.get(1)).get('success') is True) == want, r.get(1))
r = tx([(FIN, VIEW)], ON)
v = j(r.get(0))
check('the view shows the one booking awaiting a check, with its amount', [a.get('booking_id') for a in v.get('awaiting', [])] == [BW] and v['awaiting'][0]['amount'] == 980000, v)
check('the view has no proof path and no document', not re.search(r'transfer\.jpg|invoice|receipt|proof_path|document', r.get(0) or ''), r.get(0))
check('the view counts the confirmed money', v.get('confirmed_amount') == 490000 and v.get('confirmed_seats') == 1, v)

print('214: confirming, with one audit row each')
r = tx([(FIN, VERIFY.format(b=BW)), ('admin', AUDIT.format(a='confirm_payment', b=BW, u=FIN)),
        ('admin', f"(SELECT payment_state::text FROM bookings WHERE id = '{BW}')"), ('admin', f"(SELECT verified_by::text FROM bookings WHERE id = '{BW}')")], ON)
check('Finance confirms a payment awaiting a check', j(r.get(0)).get('success') is True, r.get(0))
check('one audit row', r.get(1) == '1', r.get(1))
check('the booking is confirmed and records who did it', r.get(2) == 'confirmed' and r.get(3) == FIN, r)
r = tx([(HM, CONFIRM.format(b=BW)), ('admin', AUDIT.format(a='confirm_payment', b=BW, u=HM))], ON)
check('the Attendance path (confirm_payment) works for a delegate too, audited', j(r.get(0)).get('success') is True and r.get(1) == '1', r)
r = tx([(OWNER, VERIFY.format(b=BW)), ('admin', "(SELECT count(*) FROM event_money_audit)")], ON)
check('the Host path writes no delegate audit row', j(r.get(0)).get('success') is True and r.get(1) == '0', r)
r = tx([(FIN, VERIFY.format(b=BH)), (FIN, CONFIRM.format(b=BH))], ON)
check('a delegate cannot confirm a hold nobody says they paid (verify)', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('nor through confirm_payment', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))
r = tx([(FIN, VERIFY.format(b=BW))], ON + "UPDATE bookings SET payment_state = 'disputed' WHERE id = '" + BW + "';")
check('nor a disputed payment', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))

print('214: limits on a delegate')
r = tx([(FIN, VERIFY.format(b=BW)), (OWNER, VERIFY.format(b=BW))],
       ON + f"UPDATE event_project_members SET grant_expires_at = now() - interval '1 minute' WHERE user_id = '{FIN}' AND event_id = 'pj_main';")
check('an expired grant is refused', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('the Host still confirms', j(r.get(1)).get('success') is True, r.get(1))
r = tx([(FIN, VERIFY.format(b=BP))], ON)
check('a read-only project gives no delegate rights', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
r = tx([(FIN, VERIFY.format(b=BW))], flags({'project_delegate_payments'}))
check('the payments switch alone is not enough (hub off)', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
r = tx([(FIN, VERIFY.format(b=BW))], flags({'event_project_hub', 'project_delegate_checkin'}))
check('the check-in switch does not open money', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))

print('214: rejecting stays with the organizer accounts (M3)')
r = tx([(FIN, f"public.reject_payment('{BW}', 'Not in the account')::text"), (FIN, f"public.reject_pending_guest('{BW}', 'Not in the account')::text")], ON)
check("Finance cannot say \"Can't find it\" (reject_payment)", j(r.get(0)).get('success') is not True, r.get(0))
check('Finance cannot reject a pending guest', j(r.get(1)).get('success') is not True, r.get(1))

print('214: transfer proofs (N3, M2)')
r = tx([(FIN, SEE.format(bucket='pay-proof', b=BW)), (FIN, OPEN.format(b=BW)), ('admin', AUDIT.format(a='proof_open', b=BW, u=FIN)),
        (FIN, SEE.format(bucket='pay-proof', b=BW)), (FIN, SEE.format(bucket='pay-proof', b=BC)), (FIN, SEE.format(bucket='payment-documents', b=BW)),
        (FIN, SEE.format(bucket='pay-proof', b=BH))], ON)
check('before opening, Finance cannot see the proof file', r.get(0) == '0', r.get(0))
o = j(r.get(1))
check('opening returns that booking\'s proof path', o.get('success') is True and o.get('path') == f'{BW}/transfer.jpg' and o.get('bucket') == 'pay-proof', o)
check('every open writes an audit row first', r.get(2) == '1', r.get(2))
check('after opening, Finance can read that one file', r.get(3) == '1', r.get(3))
check('never another booking\'s proof', r.get(4) == '0' and r.get(6) == '0', r)
check('never an invoice or receipt (payment-documents)', r.get(5) == '0', r.get(5))
r = tx([(FIN, OPEN.format(b=BC)), (FIN, OPEN.format(b=BH)), (HC, OPEN.format(b=BW)), (OWNER, OPEN.format(b=BW))], ON)
check('a confirmed booking\'s proof cannot be opened', j(r.get(0)).get('error') == 'NOT_AWAITING', r.get(0))
check('a hold with no claim of payment cannot be opened', j(r.get(1)).get('error') == 'NOT_AWAITING', r.get(1))
check('a check-in-only helper can never open a proof', j(r.get(2)).get('error') == 'NOT_AUTHORIZED', r.get(2))
check('the Host does not need it (pay_proof_read already lets them read)', j(r.get(3)).get('error') == 'NOT_AUTHORIZED', r.get(3))
r = tx([(FIN, '!SELECT ' + OPEN.format(b=BW)), ('admin', "!UPDATE event_money_audit SET at = now() - interval '6 minutes' WHERE action = 'proof_open'"),
        (FIN, SEE.format(bucket='pay-proof', b=BW))], ON)
check('the window closes after 5 minutes', r.get(2) == '0', r.get(2))
r = tx([(FIN, '!SELECT ' + OPEN.format(b=BW)), ('admin', f"!UPDATE bookings SET payment_state = 'confirmed' WHERE id = '{BW}'"),
        (FIN, SEE.format(bucket='pay-proof', b=BW))], ON)
check('once the booking is settled the proof is closed again', r.get(2) == '0', r.get(2))
r = tx([(FIN, '!SELECT ' + OPEN.format(b=BW)), ('admin', "!UPDATE app_feature_flags SET enabled = false WHERE key = 'project_delegate_payments'"),
        (FIN, SEE.format(bucket='pay-proof', b=BW))], ON)
check('switching delegation off closes an open proof at once', r.get(2) == '0', r.get(2))
r = tx([(OWNER, SEE.format(bucket='pay-proof', b=BW)), (OUT, SEE.format(bucket='pay-proof', b=BW))], ON)
check('the Host and the guest still read the proof as before (pay_proof_read)', r.get(0) == '1' and r.get(1) == '1', r)

print('214: originals copied verbatim, grants, re-apply, rollback')
def fn(text, name):
    i = text.index(f'CREATE OR REPLACE FUNCTION public.{name}(')
    return [l.strip() for l in text[i:text.index('$$;', i)].splitlines() if l.strip()]
mig = open(MIG).read()
for name, src in [('verify_payment', M213), ('confirm_payment', M060)]:
    old, new = fn(open(src).read(), name), fn(mig, name)
    k = 0
    for line in new:
        if k < len(old) and line == old[k]:
            k += 1
    check(f'every line of the previous {name} survives, in order (only additions)', k == len(old), old[k] if k < len(old) else '')
check('214 never calls project_is_host', 'project_is_host(' not in mig)
r = tx([('admin', f"has_function_privilege('{role}', 'public.{fn}', 'EXECUTE')")
        for role, fn in [('anon', 'get_event_money_view(text)'), ('anon', 'open_payment_proof(uuid)'), ('anon', 'verify_payment(uuid,text,text,jsonb)'),
                         ('authenticated', 'project_delegate_ok(text,text)'), ('authenticated', 'event_money_audit_add(text,uuid,uuid,text,text)')]])
check('anon gets nothing; helpers stay server-only', r and all(x == 'false' for x in r.values()), r)
r = tx([(FIN, VERIFY.format(b=BW)), (OUT, "public.verify_payment('" + BW + "', 'x', 'webhook', '{}')::text")], ON + mig + '\n' + mig)
check('re-apply: idempotent and still working', j(r.get(0)).get('success') is True, r.get(0))
check('213 stays closed after 214 (a stranger claiming webhook is refused)', j(r.get(1)).get('error') == 'NOT_AUTHORIZED', r.get(1))
r = tx([(FIN, VERIFY.format(b=BW)), (OWNER, VERIFY.format(b=BW)),
        ('admin', "(SELECT count(*) FROM pg_proc WHERE proname IN ('get_event_money_view', 'open_payment_proof', 'pay_proof_delegate_ok'))"),
        ('admin', "(SELECT count(*) FROM pg_policies WHERE policyname = 'pay_proof_read_delegate')"),
        (OUT, "public.verify_payment('" + BH + "', 'x', 'webhook', '{}')::text")], ON + open(ROLLBACK).read())
check('rollback: delegates refused again', j(r.get(0)).get('error') == 'NOT_AUTHORIZED', r.get(0))
check('rollback: the Host path still works', j(r.get(1)).get('success') is True, r.get(1))
check('rollback: the new functions and the storage policy are gone', r.get(2) == '0' and r.get(3) == '0', r)
check('rollback keeps 213 closed', j(r.get(4)).get('error') == 'NOT_AUTHORIZED', r.get(4))

print(f'214: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
