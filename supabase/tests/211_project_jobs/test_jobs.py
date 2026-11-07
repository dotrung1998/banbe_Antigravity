#!/usr/bin/env python3
"""
Migration 211 (Event Project Hub jobs, note 76) against the THROWAWAY stack (container g-db), on the 210 seed.
Every check runs as supabase_admin inside its own transaction and is rolled back. "Now" is injected (p_now), so the
18:00 digest and the 7/90-day clean-up are tested without waiting. Touches nothing remote.
Exit code 0 only if every check holds.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = os.path.join(ROOT, 'supabase/migrations/20261231000211_211_event_project_jobs.sql')
ROLLBACK = os.path.join(ROOT, 'supabase/rollbacks/20261231000211_211_revert_event_project_jobs.sql')
LIMITS = json.load(open(os.path.join(ROOT, 'src/data/projectLimits.json')))

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
T_HELP, T_FIN, T_DEL = 'c0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000003'


def psql(script):
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q',
                        '-v', 'ON_ERROR_STOP=0'], input=script, capture_output=True, text=True)
    return r.stdout, r.stderr


def tx(setup, queries):
    """Run setup + labelled queries in ONE rolled-back transaction. queries: {label: sql}. Returns {label: text}."""
    body = 'BEGIN;\n' + setup + '\n'
    for k, sql in queries.items():
        body += f"SELECT 'R|{k}|' || coalesce(({sql})::text, 'NULL');\n"
    body += 'ROLLBACK;\n'
    out, err = psql(body)
    res = {}
    for line in out.splitlines():
        m = re.match(r'R\|([^|]+)\|(.*)$', line)
        if m:
            res[m.group(1)] = m.group(2)
    if 'ERROR' in err:
        print('  sql error:', err.strip()[:400])
    return res


# 18:00 in Asia/Ho_Chi_Minh today = 11:00 UTC; the seed's people have no zone of their own, so they default to Vietnam.
AT18 = "(date_trunc('day', now() AT TIME ZONE 'Asia/Ho_Chi_Minh') + interval '18 hours') AT TIME ZONE 'Asia/Ho_Chi_Minh'"
AT17 = AT18 + " - interval '1 hour'"
VN_TODAY = "(now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date"
DIGEST = f"public.send_project_digests({AT18})"
NOTE = "(SELECT body FROM notifications WHERE recipient_id = '{u}' AND kind = 'project_digest' ORDER BY created_at DESC LIMIT 1)"
COUNT = "(SELECT count(*) FROM notifications WHERE recipient_id = '{u}' AND kind = 'project_digest')"
DATA = "(SELECT data::text FROM notifications WHERE recipient_id = '{u}' AND kind = 'project_digest' ORDER BY created_at DESC LIMIT 1)"

print('211: digest')
r = tx("UPDATE app_feature_flags SET enabled = false WHERE key = 'event_project_hub';", {'sent': DIGEST})
check('digest: switch off sends nothing', r.get('sent') == '0', r)

r = tx('', {'sent': DIGEST, 'fin': NOTE.format(u=FIN), 'fin_data': DATA.format(u=FIN), 'out': COUNT.format(u=OUT),
            'removed': COUNT.format(u=RF)})
check('digest: sends at 18:00 local', int(r.get('sent', '0')) > 0, r)
# Finance: a question addressed to them, a proposal not voted on, an update and a decision not seen = 4 posts.
check('digest: counts posts waiting on me', (r.get('fin') or '').startswith('Bạn có 4 bài đang chờ bạn ở PJ Main'), r.get('fin'))
fd = json.loads(r.get('fin_data') or '{}')
check('digest: opens the project', fd.get('screen') == 'event_project' and fd.get('event_id') == 'pj_main' and fd.get('posts') == 4, fd)
check('digest: outsiders get nothing', r.get('out') == '0', r.get('out'))
check('digest: removed members get nothing', r.get('removed') == '0', r.get('removed'))

r = tx('', {'first': DIGEST, 'second': DIGEST, 'n': COUNT.format(u=FIN)})
check('digest: once per local day', r.get('second') == '0' and r.get('n') == '1', r)

r = tx('', {'sent': f"public.send_project_digests({AT17})"})
check('digest: not at 17:00', r.get('sent') == '0', r)

r = tx(f"UPDATE profiles SET muted_notification_kinds = ARRAY['project_digest'] WHERE id = '{FIN}';",
       {'sent': DIGEST, 'fin': COUNT.format(u=FIN)})
check('digest: a muted kind stays silent', r.get('fin') == '0', r)

r = tx(f"INSERT INTO reward_user_settings (user_id, tz) VALUES ('{FIN}', 'America/New_York') ON CONFLICT (user_id) DO UPDATE SET tz = excluded.tz;",
       {'sent': DIGEST, 'fin': COUNT.format(u=FIN), 'mgr': COUNT.format(u=MGR)})
check("digest: 18:00 is on each person's own clock", r.get('fin') == '0' and r.get('mgr') == '1', r)

# Tasks: due today or tomorrow (or late) in the EVENT's zone count; the day after tomorrow doesn't.
r = tx(f"UPDATE event_project_tasks SET due_date = {VN_TODAY} + 1 WHERE id = '{T_HELP}';", {'sent': DIGEST, 'help': NOTE.format(u=HELP)})
check('digest: a task due tomorrow counts', (r.get('help') or '').startswith('Bạn có 1 việc sắp đến hạn'), r.get('help'))
r = tx(f"UPDATE event_project_tasks SET due_date = {VN_TODAY} - 3 WHERE id = '{T_HELP}';", {'sent': DIGEST, 'help': NOTE.format(u=HELP)})
check('digest: a late task counts', (r.get('help') or '').startswith('Bạn có 1 việc sắp đến hạn'), r.get('help'))
r = tx(f"UPDATE event_project_tasks SET due_date = {VN_TODAY} + 2 WHERE id = '{T_HELP}';", {'sent': DIGEST, 'help': NOTE.format(u=HELP)})
check('digest: a task due in two days does not', 'việc sắp đến hạn' not in (r.get('help') or ''), r.get('help'))
r = tx(f"UPDATE event_project_tasks SET due_date = {VN_TODAY}, status = 'done' WHERE id = '{T_HELP}';", {'sent': DIGEST, 'help': NOTE.format(u=HELP)})
check('digest: a done task does not', 'việc sắp đến hạn' not in (r.get('help') or ''), r.get('help'))

r = tx(f"UPDATE event_project_tasks SET status = 'blocked' WHERE id = '{T_FIN}';",
       {'sent': DIGEST, 'owner': NOTE.format(u=OWNER), 'second': NOTE.format(u=SECOND), 'mgr': NOTE.format(u=MGR)})
check('digest: the Host hears about blocked tasks', '1 việc bị chặn' in (r.get('owner') or ''), r.get('owner'))
check('digest: both organizer accounts are Hosts', '1 việc bị chặn' in (r.get('second') or ''), r.get('second'))
check('digest: a Manager does not get the blocked count', 'bị chặn' not in (r.get('mgr') or ''), r.get('mgr'))

r = tx("UPDATE events SET status = 'cancelled' WHERE id = 'pj_main';", {'sent': DIGEST})
check('digest: a cancelled event is skipped', r.get('sent') == '0', r)

# The past project (event 40 days ago) is read-only: its open task and posts never appear.
r = tx(f"UPDATE event_project_tasks SET due_date = {VN_TODAY} WHERE id = 'c0000000-0000-0000-0000-000000000004';",
       {'items': f"(SELECT count(*) FROM public.project_digest_items('{HELP}', {AT18}) WHERE event_id = 'pj_past')"})
check('digest: read-only projects are skipped', r.get('items') == '0', r)

r = tx(f"INSERT INTO event_project_digest_log (user_id, local_day, items) VALUES ('{FIN}', {VN_TODAY} - 20, 1), ('{MGR}', {VN_TODAY} - 3, 1);",
       {'purge': 'public.purge_project_data()::text',
        'kept': f"(SELECT count(*) FROM event_project_digest_log WHERE user_id = '{MGR}')",
        'gone': f"(SELECT count(*) FROM event_project_digest_log WHERE user_id = '{FIN}')"})
check('purge: digest log keeps 14 days', r.get('kept') == '1' and r.get('gone') == '0', r)

print('211: clean-up')
r = tx(f"UPDATE event_project_tasks SET deleted_at = now() - interval '8 days' WHERE id = '{T_DEL}';",
       {'purge': 'public.purge_project_data()::text', 'left': f"(SELECT count(*) FROM event_project_tasks WHERE id = '{T_DEL}')"})
check('purge: trash older than 7 days goes', r.get('left') == '0' and json.loads(r.get('purge') or '{}').get('tasks') == 1, r)
r = tx(f"UPDATE event_project_tasks SET deleted_at = now() - interval '6 days' WHERE id = '{T_DEL}';",
       {'purge': 'public.purge_project_data()::text', 'left': f"(SELECT count(*) FROM event_project_tasks WHERE id = '{T_DEL}')"})
check('purge: trash younger than 7 days stays', r.get('left') == '1', r)
r = tx("UPDATE event_project_posts SET deleted_at = now() - interval '8 days', deleted_by = 'a0100000-0000-0000-0000-000000000001', delete_reason = 'Old' WHERE id = 'd0000000-0000-0000-0000-000000000002';"
       "UPDATE event_project_ros_items SET deleted_at = now() - interval '8 days', deleted_by = 'a0100000-0000-0000-0000-000000000001', delete_reason = 'Old' WHERE id = '90000000-0000-0000-0000-000000000001';",
       {'purge': 'public.purge_project_data()::text'})
p = json.loads(r.get('purge') or '{}')
check('purge: old deleted posts and run-of-show items go', p.get('posts') == 1 and p.get('ros') == 1, p)
r = tx("UPDATE event_project_tasks SET status = 'done' WHERE lane_id = 'b0000000-0000-0000-0000-000000000002';"
       "UPDATE event_project_lanes SET archived_at = now() - interval '8 days', archived_by = 'a0100000-0000-0000-0000-000000000001', archive_reason = 'Merged' WHERE id = 'b0000000-0000-0000-0000-000000000002';",
       {'purge': 'public.purge_project_data()::text',
        'lane': "(SELECT count(*) FROM event_project_lanes WHERE id = 'b0000000-0000-0000-0000-000000000002')",
        'others': "(SELECT count(*) FROM event_project_lanes WHERE id = 'b0000000-0000-0000-0000-000000000001')"})
check('purge: an old archived lane goes, others stay', r.get('lane') == '0' and r.get('others') == '1', r)

r = tx("UPDATE event_project_invites SET expires_at = now() - interval '2 days' WHERE id = 'e0000000-0000-0000-0000-000000000001';"
       "UPDATE event_project_invites SET revoked_at = now() - interval '2 hours' WHERE id = 'e0000000-0000-0000-0000-000000000002';"
       f"INSERT INTO event_project_invite_attempts (user_id, at) VALUES ('{OUT}', now() - interval '2 days'), ('{OUT}', now());",
       {'purge': 'public.purge_project_data()::text',
        'expired': "(SELECT count(*) FROM event_project_invites WHERE id = 'e0000000-0000-0000-0000-000000000001')",
        'fresh_revoke': "(SELECT count(*) FROM event_project_invites WHERE id = 'e0000000-0000-0000-0000-000000000002')",
        'attempts': f"(SELECT count(*) FROM event_project_invite_attempts WHERE user_id = '{OUT}')"})
check('purge: invites expired over a day ago go', r.get('expired') == '0', r)
check('purge: a just-revoked invite stays a day', r.get('fresh_revoke') == '1', r)
check('purge: old invite attempts go', r.get('attempts') == '1', r)

r = tx('', {'purge': 'public.purge_project_data()::text', 'past': "(SELECT count(*) FROM event_projects WHERE event_id = 'pj_past')"})
check('purge: a project 39 days after its event stays (read-only)', r.get('past') == '1', r)
r = tx('', {'purge': "public.purge_project_data(now() + interval '52 days')::text",
            'past': "(SELECT count(*) FROM event_projects WHERE event_id = 'pj_past')",
            'past_rows': "(SELECT count(*) FROM event_project_members WHERE event_id = 'pj_past') + (SELECT count(*) FROM event_project_tasks WHERE event_id = 'pj_past')",
            'main': "(SELECT count(*) FROM event_projects WHERE event_id = 'pj_main')",
            'event': "(SELECT count(*) FROM events WHERE id = 'pj_past')"})
check('purge: a project 90 days after its event goes with everything in it', r.get('past') == '0' and r.get('past_rows') == '0', r)
check('purge: other projects stay', r.get('main') == '1', r)
check('purge: the event itself is never touched', r.get('event') == '1', r)

print('211: grants, schedules, limits, re-apply, rollback')
r = tx('', {f'{role}_{fn}': f"has_function_privilege('{role}', 'public.{fn}', 'EXECUTE')"
            for role in ('anon', 'authenticated') for fn in ('send_project_digests(timestamptz)', 'purge_project_data(timestamptz)',
                                                             'project_digest_items(uuid, timestamptz)')})
check('grants: jobs are server-only', r and all(v == 'false' for v in r.values()), r)
r = tx('', {'jobs': "(SELECT string_agg(jobname || '=' || schedule, ',' ORDER BY jobname) FROM cron.job WHERE jobname LIKE 'bb_project%')",
            'kinds': "(SELECT string_agg(kind || ':' || promotional, ',' ORDER BY kind) FROM notification_kind_policy WHERE kind IN ('project_digest', 'project_blocked', 'project_joined'))",
            'limits': 'public.project_limits()::text'})
check('cron: hourly digest + daily clean-up', r.get('jobs') == 'bb_project_digest=7 * * * *,bb_project_purge=17 20 * * *', r.get('jobs'))
check('kinds: three service kinds, none promotional', r.get('kinds') == 'project_blocked:false,project_digest:false,project_joined:false', r.get('kinds'))
lim = json.loads(r.get('limits') or '{}')
check('limits: digestHour matches projectLimits.json', lim.get('digestHour') == LIMITS['digestHour'], lim.get('digestHour'))
check('limits: every SQL limit matches the JSON', all(LIMITS.get(k) == v for k, v in lim.items()), {k: (v, LIMITS.get(k)) for k, v in lim.items() if LIMITS.get(k) != v})

mig = open(MIG).read()
r = tx(mig + '\n' + mig, {'jobs': "(SELECT count(*) FROM cron.job WHERE jobname LIKE 'bb_project%')",
                          'kinds': "(SELECT count(*) FROM notification_kind_policy WHERE kind IN ('project_digest', 'project_blocked', 'project_joined'))"})
check('re-apply: idempotent', r.get('jobs') == '2' and r.get('kinds') == '3', r)

r = tx(open(ROLLBACK).read(), {'jobs': "(SELECT count(*) FROM cron.job WHERE jobname LIKE 'bb_project%')",
                               'fn': "(SELECT count(*) FROM pg_proc WHERE proname IN ('send_project_digests', 'purge_project_data', 'project_digest_items'))",
                               'log': "to_regclass('public.event_project_digest_log')::text",
                               'limits': "public.project_limits() ? 'digestHour'",
                               'core': "(SELECT count(*) FROM event_projects)"})
check('rollback: removes the jobs and puts 210 limits back, project data untouched',
      r.get('jobs') == '0' and r.get('fn') == '0' and r.get('log') == 'NULL' and r.get('limits') == 'false' and r.get('core') == '2', r)

print(f'211: {PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
