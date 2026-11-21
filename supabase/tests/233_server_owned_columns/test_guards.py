#!/usr/bin/env python3
"""
Migration 233 against the THROWAWAY stack (g-db), on the 210 seed.

Every check runs in its own rolled-back transaction that first applies the
migration (or the migration then its rollback), as a real `authenticated`
caller. Exit 0 only if every check holds. Touches nothing remote.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = open(os.path.join(ROOT, 'supabase/migrations/20261231000233_233_server_owned_columns_guard.sql')).read()
RB = open(os.path.join(ROOT, 'supabase/rollbacks/20261231000233_233_revert_server_owned_columns_guard.sql')).read()
strip_tx = lambda sql: re.sub(r'(?m)^\s*(BEGIN|COMMIT);\s*$', '', sql)
MIG, RB = strip_tx(MIG), strip_tx(RB)
FAILS, PASSES = [], 0

OWNER = 'a0100000-0000-0000-0000-000000000001'   # org_pj owner_id / guest in the test thread
SECOND = 'a0200000-0000-0000-0000-000000000002' # org_pj user_id / message sender
NEW_USER = 'a0c00000-0000-0000-0000-00000000000c'
THREAD = 'a0d00000-0000-0000-0000-00000000000d'
MESSAGE = 'a0e00000-0000-0000-0000-00000000000e'
SETUP = f"""
INSERT INTO auth.users (id, email) VALUES ('{NEW_USER}', 'pj.new@example.com')
  ON CONFLICT (id) DO NOTHING;
DELETE FROM public.profiles WHERE id = '{NEW_USER}';
INSERT INTO public.account_phone_grandfathered (user_id, cohort) VALUES ('{NEW_USER}', 'test_233')
  ON CONFLICT DO NOTHING;
UPDATE public.profiles SET role = 'participant', can_manage_admins = false, phone_verified = false,
       attended_count = 0, no_show_count = 0, referral_code = 'KEEP123',
       referred_by = NULL, created_at = '2020-01-01T00:00:00Z'
 WHERE id = '{OWNER}';
UPDATE public.organizers SET verified = false, disputes_open = 0, social_links = '[]'::jsonb
 WHERE id = 'org_pj';
INSERT INTO public.threads (id, event_id, guest_id, organizer_id)
VALUES ('{THREAD}', 'pj_main', '{OWNER}', 'org_pj')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.messages (id, thread_id, sender_id, body, kind)
VALUES ('{MESSAGE}', '{THREAD}', '{SECOND}', 'original body', 'text')
ON CONFLICT (id) DO NOTHING;
CREATE SCHEMA t233;
CREATE FUNCTION t233.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
CREATE FUNCTION t233.exec(q text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE q; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN 'ERR:' || SQLERRM; END $$;
GRANT USAGE ON SCHEMA t233 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION t233.try(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION t233.exec(text) TO authenticated, service_role;
"""


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(kind):
    if kind == 'postgres':
        return 'RESET ROLE;\n'
    uid = {'auth': OWNER, 'second': SECOND, 'new': NEW_USER}[kind]
    return f"RESET ROLE;\nSELECT set_config('request.jwt.claims', {lit(json.dumps({'sub': uid, 'role': 'authenticated'}))}, true);\nSET LOCAL ROLE authenticated;\n"


def tx(steps, apply_rollback=False):
    body = 'BEGIN;\n' + MIG + '\n' + (RB + '\n' if apply_rollback else '') + SETUP
    for i, (u, q) in enumerate(steps):
        # `try` returns the row from SELECT/INSERT..RETURNING; `exec` runs a
        # plain UPDATE/DELETE (which cannot be used with INTO) and returns ok.
        fn = 'try' if re.search(r'\bRETURNING\b', q, re.I) or re.match(r'\s*SELECT\b', q, re.I) else 'exec'
        body += as_user(u) + f"SELECT 'R|{i}|' || t233.{fn}({lit(q)});\n"
    body += 'ROLLBACK;\n'
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'],
                       input=body, capture_output=True, text=True)
    if r.returncode != 0:
        print('  sql error:', r.stderr.strip()[:800])
    res = {}
    for line in r.stdout.splitlines():
        m = re.match(r'R\|(\d+)\|(.*)$', line)
        if m:
            res[int(m.group(1))] = m.group(2)
    return res


def check(name, cond, detail=''):
    global PASSES
    if cond:
        PASSES += 1
    else:
        FAILS.append(name)
        print(f'  FAIL {name} {detail}')


profile_values = (
    f"SELECT can_manage_admins::text || '|' || phone_verified::text || '|' || "
    f"attended_count::text || '|' || no_show_count::text || '|' || referral_code || '|' || "
    f"coalesce(referred_by::text, '') || '|' || created_at::text "
    f"FROM public.profiles WHERE id = '{OWNER}'"
)
organizer_values = "SELECT verified::text || '|' || disputes_open::text FROM public.organizers WHERE id = 'org_pj'"
message_body = f"SELECT body FROM public.messages WHERE id = '{MESSAGE}'"

# --- with migration 233 applied ---
r = tx([
    ('auth', "UPDATE public.profiles SET can_manage_admins = true, phone_verified = true, "
             "attended_count = 99, no_show_count = 99, referral_code = 'EVIL123', "
             "referred_by = NULL, created_at = '2000-01-01T00:00:00Z' "
             f"WHERE id = '{OWNER}'"),
    ('auth', profile_values),
    ('auth', "UPDATE public.organizers SET verified = true, disputes_open = 42 WHERE id = 'org_pj'"),
    ('auth', organizer_values),
    ('auth', "UPDATE public.profiles SET social_links = '[{\"platform\":\"x\",\"url\":\"javascript:alert(1)\"}]'::jsonb "
             f"WHERE id = '{OWNER}'"),
    ('auth', "UPDATE public.organizers SET social_links = '[{\"platform\":\"x\",\"url\":\"javascript:alert(1)\"}]'::jsonb "
             "WHERE id = 'org_pj'"),
    ('auth', f"UPDATE public.messages SET body = 'rewritten' WHERE id = '{MESSAGE}'"),
    ('auth', message_body),
    ('auth', f"UPDATE public.messages SET read_at = now() WHERE id = '{MESSAGE}'"),
    ('auth', f"INSERT INTO public.messages (thread_id, sender_id, body, kind) "
             f"VALUES ('{THREAD}', '{OWNER}', 'fake system notice', 'system') RETURNING kind"),
    ('new', f"INSERT INTO public.profiles (id, handle, role, can_manage_admins, phone_verified, attended_count, "
             f"no_show_count, referral_code, referred_by, created_at) "
             f"VALUES ('{NEW_USER}', 'pjnew', 'admin', true, true, 99, 99, 'EVIL123', '{OWNER}', '2000-01-01T00:00:00Z') "
             f"RETURNING role || '|' || can_manage_admins::text || '|' || phone_verified::text || '|' || "
             f"attended_count::text || '|' || no_show_count::text || '|' || referral_code || '|' || "
             f"coalesce(referred_by::text, '') || '|' || created_at::text"),
    # Definor/service paths must still work: a postgres update is not a client write.
    ('postgres', "UPDATE public.organizers SET verified = true, disputes_open = 42 WHERE id = 'org_pj'"),
    ('postgres', organizer_values),
    ('postgres', "UPDATE public.profiles SET can_manage_admins = true WHERE id = 'a0b00000-0000-0000-0000-00000000000b'"),
    ('postgres', "SELECT can_manage_admins::text FROM public.profiles WHERE id = 'a0b00000-0000-0000-0000-00000000000b'"),
])
check('client cannot self-grant admin-team permission', (r.get(1) or '').startswith('false|'), r.get(1))
check('client cannot self-verify phone/attendance/referral', (r.get(1) or '') == 'false|false|0|0|KEEP123||2020-01-01 00:00:00+00', r.get(1))
check('client cannot self-award organizer verified/disputes', r.get(3) == 'false|0', r.get(3))
check('direct invalid profile social link is rejected', (r.get(4) or '').startswith('ERR:INVALID_SOCIAL_LINKS'), r.get(4))
check('direct invalid organizer social link is rejected', (r.get(5) or '').startswith('ERR:INVALID_SOCIAL_LINKS'), r.get(5))
check('client cannot rewrite another participant message body', (r.get(6) or '').startswith('ERR:permission denied'), r.get(6))
check('the message body is unchanged after the rejected write', r.get(7) == 'original body', r.get(7))
check('client can still mark a message read', r.get(8) == 'ok', r.get(8))
check('client cannot insert a fake system message', r.get(9) == 'text', r.get(9))
inserted_profile = r.get(10) or ''
check('client cannot insert a privileged profile row',
      inserted_profile.startswith('participant|false|false|0|0|')
      and 'EVIL123' not in inserted_profile
      and inserted_profile.split('|')[-2] == '',
      inserted_profile)
check('definer/service path can still set verified/disputes', r.get(12) == 'true|42', r.get(12))
check('definer/service path can still set can_manage_admins', r.get(14) == 'true', r.get(14))

# --- rollback restores the old direct-write surface (proves 233 is what closed it) ---
r = tx([
    ('auth', "UPDATE public.organizers SET verified = true, disputes_open = 42 WHERE id = 'org_pj'"),
    ('auth', organizer_values),
    ('auth', f"UPDATE public.messages SET body = 'rewritten' WHERE id = '{MESSAGE}'"),
    ('auth', message_body),
], apply_rollback=True)
check('rollback restores organizer self-verification', r.get(1) == 'true|42', r.get(1))
check('rollback restores message body rewrite', r.get(3) == 'rewritten', r.get(3))

print(f'233: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
