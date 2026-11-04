#!/usr/bin/env python3
"""
Migration 212 (delegated check-in, note 76 phase 9a) against the THROWAWAY stack (container g-db), on the 210 seed.
Each check runs as a real `authenticated` caller (JWT claims + SET LOCAL ROLE) inside its own rolled-back transaction.
Touches nothing remote. Exit code 0 only if every check holds.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = os.path.join(ROOT, 'supabase/migrations/20261231000212_212_delegated_checkin.sql')
M151 = os.path.join(ROOT, 'supabase/migrations/20261201000151_151_per_attendee_tickets.sql')
ROLLBACK = os.path.join(ROOT, 'supabase/rollbacks/20261231000212_212_revert_delegated_checkin.sql')
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
B1, B2, B3, BP = ('70000000-0000-0000-0000-00000000000' + c for c in '1234')
A1, A2 = '71000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000002'
T1, T2 = '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000002'

SEED = f"""
UPDATE events SET details = jsonb_build_object('v', 1, 'min_age', '18') WHERE id = 'pj_main';
INSERT INTO bookings (id, event_id, user_id, qty, total_vnd, status) VALUES
  ('{B1}', 'pj_main', '{OUT}', 2, 980000, 'confirmed'),
  ('{B2}', 'pj_main', '{LEAD}', 2, 980000, 'confirmed'),
  ('{B3}', 'pj_main', '{HELP}', 1, 490000, 'pending'),
  ('{BP}', 'pj_past', '{OUT}', 1, 490000, 'confirmed');
INSERT INTO booking_attendees (id, booking_id, event_id, seat_no, name, date_of_birth, admission_token, ticket_code) VALUES
  ('{A1}', '{B2}', 'pj_main', 1, 'Anh Guest', '2000-01-01', '{T1}', 'PJ-T1'),
  ('{A2}', '{B2}', 'pj_main', 2, 'Binh Guest', current_date - interval '15 years', '{T2}', 'PJ-T2');
"""


def flags(on):
    keys = ['event_project_hub', 'project_delegate_checkin']
    return ''.join(f"UPDATE app_feature_flags SET enabled = {str(k in on).lower()} WHERE key = '{k}';\n" for k in keys)


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(u):
    if u == 'admin':
        return 'RESET ROLE;\n'
    if u == 'anon':
        return "SELECT set_config('request.jwt.claims', '{\"role\":\"anon\"}', true);\nSET LOCAL ROLE anon;\n"
    return f"SELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': u, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, setup=''):
    """steps: [(user, expr)]; '!' prefix = a statement. One rolled-back transaction. Returns {i: text}."""
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
        print('  sql error:', r.stderr.strip()[:400])
    return res


def j(t):
    try:
        return json.loads(t)
    except Exception:
        return None


def ok(t):
    return (j(t) or {}).get('success') is True


def err(t):
    return (j(t) or {}).get('error')


CHECKIN = "public.check_in_guest('{b}', '{src}')::text"
NAMES = "public.get_event_checkin_names('pj_main')::text"
AUDIT = "(SELECT count(*) FROM event_money_audit WHERE action = 'checkin' AND booking_id = '{b}' AND actor_id = '{u}')"
ON = flags({'event_project_hub', 'project_delegate_checkin'})

print('212: switch off — nothing changes for anyone')
r = tx([(OWNER, CHECKIN.format(b=B1, src='manual')), (FIN, CHECKIN.format(b=B2, src='manual')), (FIN, NAMES), (OWNER, NAMES)],
       flags({'event_project_hub'}))
check('owner checks in as before', ok(r.get(0)), r.get(0))
check('Finance is refused while the switch is off', err(r.get(1)) == 'Not authorized', r.get(1))
check('no door list for Finance while off', err(r.get(2)) == 'NOT_AUTHORIZED', r.get(2))
check('the Host always has the door list', ok(r.get(3)), r.get(3))
r = tx([(SECOND, CHECKIN.format(b=B1, src='manual'))], flags(set()))
check('the second organizer account checks in as before (even with the hub off)', ok(r.get(0)), r.get(0))

print('212: switch on — who may')
for who, name, want in [(FIN, 'Finance', True), (HC, 'helper with check-in', True), (HM, 'helper with money only', False), (HELP, 'helper', False),
                        (MGR, 'manager without access', False), (OUT, 'outsider', False), (RF, 'removed Finance', False)]:
    r = tx([(who, NAMES), (who, CHECKIN.format(b=B1, src='manual'))], ON)
    check(f'door list: {name}', ok(r.get(0)) == want, r.get(0))
    check(f'check-in: {name}', ok(r.get(1)) == want, r.get(1))

r = tx([(FIN, NAMES)], ON)
guests = (j(r.get(0)) or {}).get('guests') or []
check('the door list has three rows (two attendees + one party, not the pending one)', len(guests) == 3, guests)
check('the door list carries names and check-in state only', all(set(g) == {'booking_id', 'attendee_id', 'name', 'party', 'checked_in'} for g in guests), guests)
check('no amount, code, token or birth date anywhere in it', not re.search(r'total|vnd|amount|code|token|birth|dob|proof', r.get(0) or ''), r.get(0))

print('212: audit')
r = tx([(FIN, CHECKIN.format(b=B1, src='manual')), ('admin', AUDIT.format(b=B1, u=FIN)), ('admin', f"(SELECT status::text FROM bookings WHERE id = '{B1}')")], ON)
check('a delegated check-in works', ok(r.get(0)), r.get(0))
check('and writes exactly one audit row', r.get(1) == '1', r.get(1))
check('the booking is attended', r.get(2) == 'attended', r.get(2))
r = tx([(OWNER, CHECKIN.format(b=B1, src='manual')), ('admin', "(SELECT count(*) FROM event_money_audit)")], ON)
check('the Host path writes no delegate audit row', ok(r.get(0)) and r.get(1) == '0', r)
r = tx([(HC, CHECKIN.format(b=T1, src='scan')), (HC, CHECKIN.format(b=T2, src='scan')), ('admin', AUDIT.format(b=B2, u=HC)),
        (HC, CHECKIN.format(b=T2, src='scan')), ('admin', AUDIT.format(b=B2, u=HC))], ON)
check('a delegate scans each attendee in', ok(r.get(0)) and ok(r.get(1)), r)
check('one audit row per person admitted', r.get(2) == '2', r.get(2))
check('a second scan of the same person is refused and not audited', err(r.get(3)) == 'Guest already checked in' and r.get(4) == '2', r)

print('212: limits on a delegate')
r = tx([(FIN, CHECKIN.format(b=B1, src='manual')), (OWNER, CHECKIN.format(b=B1, src='manual'))],
       ON + f"UPDATE event_project_members SET grant_expires_at = now() - interval '1 minute' WHERE user_id = '{FIN}' AND event_id = 'pj_main';")
check('an expired grant is refused', err(r.get(0)) == 'Not authorized', r.get(0))
check('the Host still checks in', ok(r.get(1)), r.get(1))
r = tx([(FIN, CHECKIN.format(b=BP, src='manual'))], ON)
check('a read-only project (past event) gives no delegate rights', err(r.get(0)) == 'Not authorized', r.get(0))
r = tx([(FIN, CHECKIN.format(b=B1, src='manual'))], ON + "UPDATE events SET status = 'cancelled' WHERE id = 'pj_main';")
check('a cancelled event gives no delegate rights', err(r.get(0)) == 'Not authorized', r.get(0))
r = tx([(FIN, CHECKIN.format(b=B1, src='manual'))], flags({'project_delegate_checkin'}))
check('the delegate switch alone is not enough (hub off)', err(r.get(0)) == 'Not authorized', r.get(0))
r = tx([(FIN, CHECKIN.format(b=B3, src='manual'))], ON)
check('a pending booking stays ineligible for a delegate too', err(r.get(0)) == 'Booking is not eligible for check-in', r.get(0))
r = tx([(FIN, f"public.undo_check_in('{B1}', 'Wrong guest')::text")], ON + f"UPDATE bookings SET status = 'attended' WHERE id = '{B1}';")
check('undoing a check-in is not delegated', err(r.get(0)) == 'Not authorized', r.get(0))

print('212: scanner lookup for delegates')
r = tx([(FIN, f"public.project_checkin_lookup('{T1}')::text"), (FIN, f"public.project_checkin_lookup('{T2}')::text"),
        (HM, f"public.project_checkin_lookup('{T1}')::text"), (FIN, f"public.project_checkin_lookup('{B3}')::text")], ON)
a, b = j(r.get(0)) or {}, j(r.get(1)) or {}
check('lookup: name and a yes for an adult', a.get('name') == 'Anh Guest' and a.get('meets_min_age') is True and a.get('min_age') == 18, a)
check('lookup: a no for a 15-year-old at an 18+ event', b.get('meets_min_age') is False, b)
check('lookup never returns a birth date or amount', not re.search(r'birth|dob|total|vnd|amount|token', (r.get(0) or '') + (r.get(1) or '')), r.get(0))
check('lookup: a money-only helper gets nothing', err(r.get(2)) == 'NOT_FOUND', r.get(2))
check('lookup: a pending booking is not eligible', err(r.get(3)) == 'NOT_ELIGIBLE', r.get(3))

print('212: grant extension (Host)')
r = tx([(OWNER, "public.project_extend_grants('pj_main', now() + interval '1 day')::text"),
        ('admin', "(SELECT count(*) FROM event_money_audit WHERE action = 'extend_grants' AND actor_id = '" + OWNER + "')"),
        (OWNER, "public.project_extend_grants('pj_main', now() + interval '400 days')::text"),
        (FIN, "public.project_extend_grants('pj_main', now() + interval '1 day')::text"),
        (SECOND, "public.project_extend_grants('pj_main', now() + interval '2 days')::text")], ON)
check('the Host extends grants', ok(r.get(0)) and (j(r.get(0)) or {}).get('members') == 3, r.get(0))
check('with one audit row', r.get(1) == '1', r.get(1))
check('never past read-only', err(r.get(2)) == 'INVALID_VALUE', r.get(2))
check('a delegate cannot extend', err(r.get(3)) == 'NOT_AUTHORIZED', r.get(3))
check('the second organizer account is a Host here too', ok(r.get(4)), r.get(4))
r = tx([(FIN, CHECKIN.format(b=B1, src='manual'))],
       ON + f"UPDATE event_project_members SET grant_expires_at = now() - interval '1 minute' WHERE user_id = '{FIN}';"
       + f"SELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': OWNER, 'role': 'authenticated'}))}, true); SET LOCAL ROLE authenticated;"
       + "SELECT public.project_extend_grants('pj_main', now() + interval '1 day'); RESET ROLE;")
check('an extended grant works again', ok(r.get(0)), r.get(0))

print('212: the audit table is read-only and private')
r = tx([('admin', "has_table_privilege('authenticated', 'public.event_money_audit', 'INSERT')"),
        ('admin', "has_table_privilege('authenticated', 'public.event_money_audit', 'UPDATE')"),
        ('admin', "has_table_privilege('authenticated', 'public.event_money_audit', 'DELETE')"),
        (FIN, '!SELECT ' + CHECKIN.format(b=B1, src='manual')),
        (OWNER, "(SELECT count(*) FROM event_money_audit)"), (FIN, "(SELECT count(*) FROM event_money_audit)"),
        (OUT, "(SELECT count(*) FROM event_money_audit)")], ON)
check('nobody can insert, update or delete audit rows from a client', [r.get(0), r.get(1), r.get(2)] == ['false', 'false', 'false'], r)
check('the Host reads the audit', r.get(4) == '1', r.get(4))
check('the delegate and outsiders do not', r.get(5) == '0' and r.get(6) == '0', r)
r = tx([('admin', f"has_function_privilege('{role}', 'public.{fn}', 'EXECUTE')")
        for role in ('anon', 'authenticated') for fn in ('can_event_capability(text, text)', 'project_delegate_ok(text, text)',
                                                         'event_money_audit_add(text, uuid, uuid, text, text)')]
       + [('admin', "has_function_privilege('anon', 'public.get_event_checkin_names(text)', 'EXECUTE')")])
check('helpers are server-only; anon gets no door list', r and all(v == 'false' for v in r.values()), r)

print('212: the Host check is copied verbatim from 151')
def fn(text):
    i = text.index('CREATE OR REPLACE FUNCTION public.check_in_guest(p_reservation_id uuid')
    return text[i:text.index('$$;', i)]
old = [l.strip() for l in fn(open(M151).read()).splitlines() if l.strip()]
new = [l.strip() for l in fn(open(MIG).read()).splitlines() if l.strip()]
k = 0
for line in new:
    if k < len(old) and line == old[k]:
        k += 1
check('every line of 151 check_in_guest survives, in order (only additions)', k == len(old), old[k] if k < len(old) else '')
check('the owner_id-or-user_id line is untouched', "WHERE e.id = v_booking.event_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())" in new)
check('212 never calls project_is_host', 'project_is_host(' not in open(MIG).read().split('project_extend_grants')[0])

print('212: re-apply and rollback')
mig = open(MIG).read()
r = tx([(FIN, CHECKIN.format(b=B1, src='manual'))], ON + mig + '\n' + mig)
check('re-apply: idempotent and still working', ok(r.get(0)), r.get(0))
r = tx([(FIN, CHECKIN.format(b=B1, src='manual')), (OWNER, CHECKIN.format(b=B2, src='manual')),
        ('admin', "(SELECT count(*) FROM pg_proc WHERE proname IN ('get_event_checkin_names', 'project_delegate_ok', 'can_event_capability'))"),
        ('admin', "to_regclass('public.event_money_audit')::text")], ON + open(ROLLBACK).read())
check('rollback: delegates refused again', err(r.get(0)) == 'Not authorized', r.get(0))
check('rollback: the Host path still works', ok(r.get(1)), r.get(1))
check('rollback: helpers and RPCs gone, the audit table kept', r.get(2) == '0' and r.get(3) == 'event_money_audit', r)

print(f'212: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
