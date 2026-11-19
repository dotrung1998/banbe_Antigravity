#!/usr/bin/env python3
"""
Migration 229 against the THROWAWAY stack (g-db), on the 210 seed. Each check runs in a rolled-back transaction that
applies the migration (or migration then rollback) and inserts a storage object AS A REAL `authenticated` caller, so
the policy is what decides. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000229_229_event_photos_insert_scope.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000229_229_revert_event_photos_insert_scope.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0
OWNER = 'a0100000-0000-0000-0000-000000000001'
FELLOW = 'a0200000-0000-0000-0000-000000000002'  # member of org_pj, not its owner
FAILS_LIST = []


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def tx(uid, path, apply_rollback=False, extra=''):
    claims = lit(json.dumps({'sub': uid, 'role': 'authenticated'}))
    body = ('BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + extra +
            "SELECT set_config('request.jwt.claims', " + claims + ", true);\nSET LOCAL ROLE authenticated;\n"
            "INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('event-photos', " + lit(path) + ", '" + uid + "');\n"
            "ROLLBACK;\n")
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'],
                       input=body, capture_output=True, text=True)
    return r.returncode, (r.stderr or '').strip()


def check(name, cond, detail=''):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS_LIST.append(name)
        print(f'  FAIL {name} {detail[:300]}')


rc, err = tx(OWNER, 'pj_main/1712345678.jpg')
check('the host uploads into their own event', rc == 0, err)

rc, err = tx(OWNER, 'pj_past/1712345678.jpg')
check('the host uploads into their own past event too', rc == 0, err)

rc, err = tx(FELLOW, 'pj_main/1712345678.jpg')
# `user_id` on the organizer is the app's second host identity (005, 093 and every RLS policy treat it as a host), so the
# org's own account may upload too — the fix narrows WHICH events, not who counts as a host.
check('the org account uploads into its own event', rc == 0, err)

rc, err = tx(OWNER, 'not-an-event/1712345678.jpg')
check('an unknown folder is refused', rc != 0, err)

extra = ("INSERT INTO public.organizers (id, name, owner_id, user_id) VALUES "
         "('org_other', 'Other', 'a0400000-0000-0000-0000-000000000004', NULL);\n"
         "INSERT INTO public.events (id, organizer_id, name, status, event_date, event_time, starts_at) VALUES "
         "('other_ev', 'org_other', 'Other', 'live', current_date + 3, '19:00', now() + interval '3 days');\n")
rc, err = tx(OWNER, 'other_ev/1712345678.jpg', extra=extra)
check('another host\'s event folder is refused', rc != 0, err)

rc, err = tx(OWNER, 'other_ev/1712345678.jpg', apply_rollback=True, extra=extra)
check('rollback lets any organizer upload anywhere (proves the fix)', rc == 0, err)

print(f'229: {PASSES} passed, {len(FAILS_LIST)} failed')
sys.exit(1 if FAILS_LIST else 0)
