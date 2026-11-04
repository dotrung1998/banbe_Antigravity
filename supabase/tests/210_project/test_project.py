#!/usr/bin/env python3
"""
Migration 210 (Event Project Hub core, note 76) against the THROWAWAY real-Supabase stack (gate_e2e/stack_up.sh,
container g-db). Every attempt runs as a real `authenticated` caller (JWT claims + SET LOCAL ROLE) inside its own
transaction and is rolled back, so the seed (10_seed.sql) never changes. Touches nothing remote.

1. The shared permission matrix (tests/fixtures/project-permissions.json): every project action, every actor, under
   BOTH Host definitions. The second pass replaces project_host_ids() with the owner_id-only body inside the
   transaction: if that one function is the only thing to change, the whole matrix still matches.
2. Scenarios: channels vectors, limits, RLS, invites, trash, caps, start, versions, notifications, decisions,
   proposals, run-of-show time rules, idempotent re-apply, rollback, and a lint on owner_id use.
Exit code 0 only if every check holds.
"""
import json, os, re, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../..'))
MIG = os.path.join(ROOT, 'supabase/migrations/20261231000210_210_event_project_core.sql')
ROLLBACK = os.path.join(ROOT, 'supabase/rollbacks/20261231000210_210_revert_event_project_core.sql')
ROLLBACK_211 = os.path.join(ROOT, 'supabase/rollbacks/20261231000211_211_revert_event_project_jobs.sql')
ROLLBACK_212 = os.path.join(ROOT, 'supabase/rollbacks/20261231000212_212_revert_delegated_checkin.sql')
FX = json.load(open(os.path.join(ROOT, 'tests/fixtures/project-permissions.json')))
CH = json.load(open(os.path.join(ROOT, 'tests/fixtures/project-channel-links.json')))
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


USERS = {'u_owner': uid(1), 'u_second': uid(2), 'u_mgr': uid(3), 'u_fin': uid(4), 'u_lead': uid(5), 'u_help': uid(6),
         'u_hm': uid(7), 'u_hc': uid(8), 'u_rf': uid(9), 'u_out': uid(10), 'u_join': uid(11)}
ACTOR_UID = {k: USERS[a['userId']] for k, a in FX['actors'].items()}
L_MENU, L_VENUE, L_MENU_P = 'b0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000003'
T_HELP_VENUE, T_FIN_MENU, T_DEL, T_PAST = (f'c0000000-0000-0000-0000-00000000000{i}' for i in range(1, 5))
P_Q, P_QUIET, P_UPD, P_PROP, P_PROP_RES, P_DEC = (f'd0000000-0000-0000-0000-00000000000{i}' for i in range(1, 7))
I_MGR, I_OWN = 'e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000002'
R1 = 'f0000000-0000-0000-0000-000000000001'
ROS_MAIN, ROS_PAST = '90000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000002'
FLAGS5 = ['event_project_hub', 'project_qr_invite', 'project_delegate_checkin', 'project_delegate_payments', 'project_delegate_refunds']
OWNER_ONLY = """CREATE OR REPLACE FUNCTION public.project_host_ids(p_event_id text)
RETURNS uuid[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $f$
  SELECT coalesce((SELECT array_remove(ARRAY[o.owner_id], NULL)
                     FROM events e JOIN organizers o ON o.id = e.organizer_id WHERE e.id = p_event_id), ARRAY[]::uuid[]);
$f$;"""


def psql(script):
    r = subprocess.run(['docker', 'exec', '-i', 'g-db', 'psql', '-U', 'supabase_admin', '-d', 'postgres', '-At', '-q',
                        '-v', 'ON_ERROR_STOP=0'], input=script, capture_output=True, text=True)
    return r.stdout, r.stderr


def q(sql):
    out, err = psql(sql)
    if err.strip() and 'NOTICE' not in err:
        print('  admin query error:', err.strip()[:300])
    return out.strip()


def lit(s):
    return "'" + str(s).replace("'", "''") + "'"


def as_user(u):
    if u == 'admin':
        return 'RESET ROLE;\n'
    if u == 'anon':
        return "SELECT set_config('request.jwt.claims', '{\"role\":\"anon\"}', true);\nSET LOCAL ROLE anon;\n"
    claims = json.dumps({'sub': u, 'role': 'authenticated'})
    return f"SELECT set_config('request.jwt.claims', {lit(claims)}, true);\nSET LOCAL ROLE authenticated;\n"


def flags_sql(flags):
    on = [k for k in FLAGS5 if flags.get(k)]
    return (f"UPDATE public.app_feature_flags SET enabled = (key = ANY (ARRAY[{','.join(lit(k) for k in on)}]::text[])) "
            f"WHERE key IN ({','.join(lit(k) for k in FLAGS5)});\n")


def transaction(steps, setup=''):
    """steps: [(user, expr)] run in ONE rolled-back transaction. Returns {index: text-or-None}."""
    body = 'BEGIN;\n' + setup
    for i, (u, expr) in enumerate(steps):
        if expr.startswith('!'):
            body += as_user(u) + expr[1:].rstrip(';') + f";\nSELECT 'R|{i}|done';\n"
        else:
            body += as_user(u) + f"SELECT 'R|{i}|' || coalesce(({expr})::text, 'NULL');\n"
    body += 'ROLLBACK;\n'
    out, err = psql(body)
    res = {}
    for line in out.splitlines():
        m = re.match(r'R\|(\d+)\|(.*)$', line)
        if m:
            res[int(m.group(1))] = m.group(2)
    return res, err


def j(text):
    try:
        return json.loads(text)
    except Exception:
        return None


# ------------------------------------------------------------------ 1. the shared matrix
MONEY = {'checkin', 'money.view', 'money.confirm', 'money.reject', 'proof.open', 'refund.request', 'refund.markSent',
         'refund.approve', 'refund.approval.set', 'grants.extend', 'event.cancel'}
HOSTS = ['owner_account', 'second_account']
ALL = HOSTS + [k for k, a in FX['actors'].items() if (a.get('member') or {}).get('status') == 'active']
READ_ONLY_AT = FX['defaults']['project']['readOnlyAt']


def expand(lst):
    out = []
    for x in lst:
        out += HOSTS if x == '@hosts' else ALL if x == '@all' else [x]
    return set(out)


MEMBER_ID = {}
for row in q("SELECT user_id || '|' || id FROM event_project_members WHERE event_id = 'pj_main'").splitlines():
    u, i = row.split('|')
    MEMBER_ID[u] = i


def call(action, actor, row, past):
    ev = 'pj_past' if past else 'pj_main'
    t = row.get('target', {})
    lane = {'venue': L_VENUE}.get(t.get('laneId'), L_MENU_P if past else L_MENU)
    me = ACTOR_UID[actor]
    addressee = USERS['u_mgr'] if me == USERS['u_owner'] else USERS['u_owner']
    start = f"(((current_date + 11) + time '18:30') AT TIME ZONE 'Asia/Ho_Chi_Minh')"
    end = f"(((current_date + 11) + time '19:30') AT TIME ZONE 'Asia/Ho_Chi_Minh')"
    return {
        'project.read': f"public.get_event_project('{ev}')",
        'channels.open': f"public.get_event_project('{ev}')",
        'project.start': "public.start_event_project('pj_new', ARRAY['Menu'])",
        'task.status': f"public.project_set_task_status('{T_HELP_VENUE if t.get('assigneeId') == 'u_help' else T_FIN_MENU}', 'blocked')",
        'task.manage': f"public.project_upsert_task('{ev}', '{T_PAST if past else (T_HELP_VENUE if t.get('laneId') == 'venue' else T_FIN_MENU)}', '{lane}', 'Edited title', NULL, NULL, NULL)",
        'post.question': f"public.project_create_post('{ev}', 'question', '{lane}', 'A test question', '', NULL, '{addressee}')",
        'post.update': f"public.project_create_post('{ev}', 'update', '{lane}', 'A test update')",
        'post.vote': f"public.project_vote('{P_PROP}', 0)",
        'post.seen': f"public.project_mark_seen('{P_UPD}')",
        'post.reply': f"public.project_reply('{P_Q}', 'Thanks')",
        'post.proposal': f"public.project_create_post('{ev}', 'proposal', '{lane}', 'Pick one', '', ARRAY['A', 'B'])",
        'post.decision': f"public.project_create_post('{ev}', 'decision', '{lane}', 'Decided thing')",
        'post.resolve': f"public.project_resolve_post('{ {'question': P_Q, 'update': P_UPD}.get(t.get('type'), P_PROP_RES) }')",
        'post.edit': f"public.project_edit_post('{P_DEC if t.get('type') == 'decision' else (P_QUIET if t.get('quiet') else P_Q)}', 'Edited title', '')",
        'post.delete': f"public.project_delete_post('{P_QUIET if t.get('quiet') else P_Q}', 'Written wrong')",
        'invite.create': f"public.project_create_invite('{ev}', {lit(t.get('role'))}, {lit(L_MENU) if t.get('role') == 'lane_lead' else 'NULL'}, 1)",
        'invite.revoke': f"public.project_revoke_invite('{I_MGR if t.get('createdBy') == 'u_mgr' else I_OWN}')",
        'member.manage': f"public.project_set_member('{MEMBER_ID[USERS['u_help']]}', 'helper', NULL, true, NULL)",
        'lane.manage': f"public.project_add_lane('{ev}', 'Marketing two')",
        'channels.edit': f"public.project_set_channels('{ev}', '[{{\"url\": \"https://t.me/team\"}}]')",
        'change.propose': f"public.project_propose_change('{ev}', 'lane_add', NULL, '{{\"name\": \"Photos\"}}', 'Need photos')",
        'change.review': f"public.project_review_change('{R1}', true, NULL)",
        'ros.edit': f"public.project_upsert_ros_item('{ev}', NULL, 'Doors open', NULL, {start}, {end})",
        'ros.tick': f"public.project_tick_ros_item('{ROS_PAST if past else ROS_MAIN}', true)",
        'trash.restore': f"public.project_restore('task', '{T_DEL}')",
        'trash.purge': f"public.project_purge('task', '{T_DEL}')",
    }[action]


matrix_rows = [r for r in FX['rows'] if r['action'] not in MONEY]
denied_codes = {}
for host_def in ['either', 'owner_only']:
    for row in matrix_rows:
        past = row.get('now', '') >= READ_ONLY_AT
        flags = row.get('flags', FX['defaults']['flags'])
        allowed = expand(row['allow']) if host_def == 'either' else (
            expand(row['allowOwnerOnly']) if 'allowOwnerOnly' in row else expand(row['allow']) - {'second_account'})
        script, keys = '', []
        for actor in FX['actors']:
            setup = flags_sql(flags) + (OWNER_ONLY + '\n' if host_def == 'owner_only' else '')
            script += 'BEGIN;\n' + setup + as_user(ACTOR_UID[actor]) + \
                f"SELECT 'R|{actor}|' || coalesce(({call(row['action'], actor, row, past)})::text, 'NULL');\nROLLBACK;\n"
            keys.append(actor)
        out, err = psql(script)
        got = {m.group(1): m.group(2) for m in (re.match(r'R\|([a-z_]+)\|(.*)$', l) for l in out.splitlines()) if m}
        for actor in keys:
            res = j(got.get(actor, ''))
            ok = bool(res and res.get('success') is True)
            if res is None:
                check(f'[{host_def}] {row["case"]}: {actor}', False, f'no result (exception?) {err.strip()[:200]}')
                continue
            if not ok:
                denied_codes[res.get('error')] = denied_codes.get(res.get('error'), 0) + 1
            check(f'[{host_def}] {row["case"]}: {actor} → {row["action"]}', ok == (actor in allowed),
                  f'expected {actor in allowed}, got {res}')
print(f'matrix: {len(matrix_rows)} rows x {len(FX["actors"])} actors x 2 Host definitions; denials by code: {denied_codes}')
check('denials only ever use refusal codes, never a validation error', set(denied_codes) <= {'NOT_AUTHORIZED', 'FEATURE_OFF', 'READ_ONLY', 'NOT_FOUND', 'NOT_OPEN', 'ALREADY_ANSWERED'},
      str(denied_codes))

# ------------------------------------------------------------------ 2. scenarios
O, S, M, F, LD, H, RF, OUT, JN = (USERS[k] for k in ['u_owner', 'u_second', 'u_mgr', 'u_fin', 'u_lead', 'u_help', 'u_rf', 'u_out', 'u_join'])


def run(name, steps, expect, setup=''):
    res, err = transaction(steps, setup)
    vals = [res.get(i) for i in range(len(steps))]
    try:
        ok = expect(vals)
    except Exception as e:  # noqa: BLE001
        ok = False
        err = f'{e} {err}'
    check(name, ok, f'got {vals} {err.strip()[:300]}')


def err_of(v):
    d = j(v)
    return d.get('error') if isinstance(d, dict) else None


def ok_of(v):
    d = j(v)
    return isinstance(d, dict) and d.get('success') is True


# channels vectors (same file as web and iOS)
for c in CH['lists']:
    res, _ = transaction([('admin', f"public.sanitize_project_channels({lit(json.dumps(c['in']))}::jsonb) IS NOT NULL")])
    check(f'channels list: {c["case"]}', res.get(0) == ('true' if c['ok'] else 'false'), str(res))
for c in CH['channels']:
    res, _ = transaction([('admin', f"public.sanitize_project_channels({lit(json.dumps([c['in']]))}::jsonb)")])
    got = j(res.get(0)) if res.get(0) not in (None, 'NULL') else None
    check(f'channel: {c["case"]}', (got[0] == c['out']) if c['ok'] else got is None, f'got {got}')
for c in CH['detect']:
    res, _ = transaction([('admin', f"(public.sanitize_project_channels({lit(json.dumps([{'url': c['url']}]))}::jsonb) -> 0 ->> 'platform')")])
    check(f'channel detect: {c["url"]}', (res.get(0) if res.get(0) != 'NULL' else None) == c['platform'], str(res))

# limits: every SQL limit equals the shared JSON
sql_limits = j(q('SELECT public.project_limits()'))
check('every SQL limit exists in src/data/projectLimits.json with the same value',
      all(LIMITS.get(k) == v for k, v in sql_limits.items()), str({k: (v, LIMITS.get(k)) for k, v in sql_limits.items() if LIMITS.get(k) != v}))

# RLS
run('RLS: an outsider reads no project rows', [(OUT, "(SELECT count(*) FROM public.event_project_tasks)"), (OUT, "(SELECT count(*) FROM public.event_projects)")],
    lambda v: v == ['0', '0'])
run('RLS: a member reads their project', [(H, "(SELECT count(*) FROM public.event_project_tasks WHERE event_id = 'pj_main' AND deleted_at IS NULL)")],
    lambda v: v == ['2'])
run('RLS: a removed member reads nothing', [(RF, "(SELECT count(*) FROM public.event_project_tasks)")], lambda v: v == ['0'])
run('RLS: hub switch off hides everything', [(H, "(SELECT count(*) FROM public.event_project_tasks)")], lambda v: v == ['0'],
    setup=flags_sql({}))
run('RLS: invites are visible to the Host (all) and to their creator (own) only',
    [(H, "(SELECT count(*) FROM public.event_project_invites)"), (M, "(SELECT count(*) FROM public.event_project_invites)"),
     (O, "(SELECT count(*) FROM public.event_project_invites)"), (S, "(SELECT count(*) FROM public.event_project_invites)")],
    lambda v: v == ['0', '1', '2', '2'])
run('RLS: proposals are visible to the Host and the proposer only',
    [(H, "(SELECT count(*) FROM public.event_project_change_requests)"), (M, "(SELECT count(*) FROM public.event_project_change_requests)"),
     (O, "(SELECT count(*) FROM public.event_project_change_requests)")], lambda v: v == ['0', '1', '1'])
for who, label in [('anon', 'anon'), (H, 'a member')]:
    res, err = transaction([(who, "(SELECT count(*) FROM public.event_project_invite_attempts)")])
    check(f'RLS: {label} cannot read invite attempts', 0 not in res and 'permission denied' in err, f'{res} {err[:120]}')
res, err = transaction([('anon', "(SELECT count(*) FROM public.event_project_tasks)")])
check('RLS: anon cannot read project tables at all', 0 not in res and 'permission denied' in err, f'{res} {err[:120]}')
res, err = transaction([(H, f"!INSERT INTO public.event_project_tasks (event_id, lane_id, title) VALUES ('pj_main', '{L_MENU}', 'Sneaky')")])
check('RLS: direct inserts are refused (writes only through RPCs)', 0 not in res and 'permission denied' in err, f'{res} {err[:120]}')
res, err = transaction([(H, "public.project_touch('pj_main', 'x', NULL, NULL)")])
check('internal helpers are not callable by clients', 0 not in res and 'permission denied' in err, f'{res} {err[:120]}')

# invites
run('invite: create, peek, redeem; a single-use invite cannot be used twice',
    [(O, "public.project_create_invite('pj_main', 'helper', NULL, 1)"),
     ('admin', "set_config('pj.token', (SELECT token FROM public.event_project_invites WHERE created_by = '%s' ORDER BY created_at DESC LIMIT 1), true)" % O),
     (JN, "public.peek_project_invite(current_setting('pj.token'))"),
     (JN, "public.project_redeem_invite(current_setting('pj.token'))"),
     (JN, "public.project_redeem_invite(current_setting('pj.token'))"),
     (OUT, "public.project_redeem_invite(current_setting('pj.token'))"),
     ('admin', f"(SELECT role || ',' || cap_money FROM public.event_project_members WHERE user_id = '{JN}' AND event_id = 'pj_main')"),
     ('admin', f"(SELECT count(*) FROM public.notifications WHERE recipient_id = '{O}' AND kind = 'project_joined')")],
    lambda v: ok_of(v[0]) and j(v[2])['state'] == 'ok' and j(v[2])['role'] == 'helper' and ok_of(v[3])
    and err_of(v[4]) == 'INVITE_USED' and err_of(v[5]) == 'INVITE_USED' and v[6] == 'helper,false' and v[7] == '1')
run('invite: the typed code works in any case and spacing',
    [(O, "public.project_create_invite('pj_main', 'helper', NULL, 1)"),
     ('admin', "set_config('pj.code', (SELECT lower(replace(short_code, '-', ' ')) FROM public.event_project_invites WHERE created_by = '%s' ORDER BY created_at DESC LIMIT 1), true)" % O),
     (JN, "public.project_redeem_invite(current_setting('pj.code'))")],
    lambda v: ok_of(v[2]))
run('invite: expired, revoked (token) and revoked (code no longer exists)',
    [(O, "public.project_create_invite('pj_main', 'helper', NULL, 1)"),
     ('admin', "set_config('pj.token', (SELECT token FROM public.event_project_invites WHERE created_by = '%s' ORDER BY created_at DESC LIMIT 1), true)" % O),
     ('admin', "set_config('pj.code', (SELECT short_code FROM public.event_project_invites WHERE created_by = '%s' ORDER BY created_at DESC LIMIT 1), true)" % O),
     ('admin', "!UPDATE public.event_project_invites SET expires_at = now() - interval '1 minute' WHERE token = current_setting('pj.token')"),
     (JN, "public.project_redeem_invite(current_setting('pj.token'))"),
     (JN, "public.peek_project_invite(current_setting('pj.token'))"),
     ('admin', "!UPDATE public.event_project_invites SET expires_at = now() + interval '1 hour', revoked_at = now() WHERE token = current_setting('pj.token')"),
     (JN, "public.project_redeem_invite(current_setting('pj.token'))"),
     (JN, "public.project_redeem_invite(current_setting('pj.code'))")],
    lambda v: err_of(v[4]) == 'INVITE_EXPIRED' and j(v[5])['state'] == 'expired' and err_of(v[7]) == 'INVITE_REVOKED' and err_of(v[8]) == 'INVITE_NOT_FOUND')
run('invite: multi-use needs the QR switch, and caps at 20',
    [(O, "public.project_create_invite('pj_main', 'helper', NULL, 5)"),
     ('admin', "!UPDATE public.app_feature_flags SET enabled = true WHERE key = 'project_qr_invite'"),
     (O, "public.project_create_invite('pj_main', 'helper', NULL, 20)"),
     (O, "public.project_create_invite('pj_main', 'helper', NULL, 21)")],
    lambda v: err_of(v[0]) == 'FEATURE_OFF' and ok_of(v[2]) and j(v[2])['max_uses'] == 20 and err_of(v[3]) == 'INVALID_VALUE')
run('invite: the Host cannot redeem; an active member cannot redeem again; a lane lead invite needs a lane',
    [(O, "public.project_redeem_invite('OwnInviteToken00000000')"),
     (S, "public.project_redeem_invite('OwnInviteToken00000000')"),
     (H, "public.project_redeem_invite('OwnInviteToken00000000')"),
     (O, "public.project_create_invite('pj_main', 'lane_lead', NULL, 1)"),
     (O, f"public.project_create_invite('pj_main', 'lane_lead', '{L_MENU}', 1)")],
    lambda v: err_of(v[0]) == 'IS_HOST' and err_of(v[1]) == 'IS_HOST' and err_of(v[2]) == 'ALREADY_MEMBER'
    and err_of(v[3]) == 'LANE_REQUIRED' and ok_of(v[4]) and j(v[4])['lane_id'] == L_MENU)
run('invite: a removed member who is invited again comes back with the new role and no money access',
    [(RF, "public.project_redeem_invite('OwnInviteToken00000000')"),
     ('admin', f"(SELECT role || ',' || status || ',' || cap_money || ',' || cap_checkin FROM public.event_project_members WHERE user_id = '{RF}' AND event_id = 'pj_main')")],
    lambda v: ok_of(v[0]) and v[1] == 'helper,active,false,false')
run('invite: 10 failed guesses in an hour lock peeks and redeems, even with a real token',
    [(JN, f"public.project_redeem_invite('BB-ZZZ{c}')") for c in 'ABCDEFGHJK'] +
    [(JN, "public.project_redeem_invite('OwnInviteToken00000000')"), (JN, "public.peek_project_invite('OwnInviteToken00000000')")],
    lambda v: all(err_of(x) == 'INVITE_NOT_FOUND' for x in v[:10]) and err_of(v[10]) == 'RATE_LIMITED' and err_of(v[11]) == 'RATE_LIMITED')
run('invite: the event closed means no joining',
    [('admin', "!UPDATE public.events SET status = 'cancelled' WHERE id = 'pj_main'"),
     (JN, "public.project_redeem_invite('OwnInviteToken00000000')")], lambda v: err_of(v[1]) == 'EVENT_CLOSED')

# caps and trash
run('lanes: 10 at most, names unique ignoring case and spaces',
    [(O, f"public.project_add_lane('pj_main', 'Lane {i}')") for i in range(3, 11)] +
    [(O, "public.project_add_lane('pj_main', 'Lane 11')"), (O, f"public.project_rename_lane('{L_VENUE}', ' menu ')")],
    lambda v: all(ok_of(x) for x in v[:8]) and err_of(v[8]) == 'LANES_FULL' and err_of(v[9]) == 'LANE_NAME_TAKEN')
run('replies: 10 per post at most',
    [('admin', f"!INSERT INTO public.event_project_post_replies (post_id, author_id, body) SELECT '{P_Q}', '{O}', 'r' || g FROM generate_series(1, 9) g"),
     (H, f"public.project_reply('{P_Q}', 'One more')")], lambda v: v[0] == 'done' and err_of(v[1]) == 'REPLIES_FULL')
run('trash keeps the 30 newest deleted items',
    [('admin', f"!INSERT INTO public.event_project_tasks (id, event_id, lane_id, title) SELECT ('c1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'pj_main', '{L_MENU}', 'Bulk ' || g FROM generate_series(1, 31) g")] +
    [(O, f"public.project_delete_task('c1000000-0000-0000-0000-{g:012d}', 'Cleanup')") for g in range(1, 32)] +
    [('admin', "(SELECT count(*) FROM public.event_project_tasks WHERE event_id = 'pj_main' AND deleted_at IS NOT NULL)"),
     ('admin', f"(SELECT count(*) FROM public.event_project_tasks WHERE id = '{T_DEL}')")],
    lambda v: all(ok_of(x) for x in v[1:32]) and v[32] == '30' and v[33] == '0')
run('delete needs a reason; restore into an archived lane is refused; archiving needs no open tasks',
    [(O, f"public.project_delete_task('{T_FIN_MENU}', ' x ')"),
     (O, f"public.project_archive_lane('{L_MENU}', 'Merged away')"),
     (O, f"public.project_upsert_task('pj_main', '{T_FIN_MENU}', '{L_MENU}', 'Confirm paid guests', NULL, NULL, 'done')"),
     (O, f"public.project_archive_lane('{L_MENU}', 'Merged away')"),
     (O, f"public.project_restore('task', '{T_DEL}')"),
     (O, f"public.project_restore('lane', '{L_MENU}')"),
     (O, f"public.project_restore('task', '{T_DEL}')")],
    lambda v: err_of(v[0]) == 'REASON_REQUIRED' and err_of(v[1]) == 'LANE_HAS_OPEN_TASKS' and ok_of(v[2]) and ok_of(v[3])
    and err_of(v[4]) == 'RESTORE_LANE_FIRST' and ok_of(v[5]) and ok_of(v[6]))

# start
run('start: opt-in, Host only, never twice, never for a cancelled or read-only event; starting lanes are de-duplicated',
    [(O, "public.start_event_project('pj_main')"), (O, "public.start_event_project('pj_cancelled')"),
     ('admin', "!DELETE FROM public.event_projects WHERE event_id = 'pj_past'"),
     (O, "public.start_event_project('pj_past')"), (H, "public.start_event_project('pj_new')"),
     (S, "public.start_event_project('pj_new', ARRAY['Menu', ' menu ', '', 'Venue'])"),
     ('admin', "(SELECT string_agg(name, ',' ORDER BY position) FROM public.event_project_lanes WHERE event_id = 'pj_new')")],
    lambda v: err_of(v[0]) == 'ALREADY_STARTED' and err_of(v[1]) == 'EVENT_CLOSED' and err_of(v[3]) == 'READ_ONLY'
    and err_of(v[4]) == 'NOT_AUTHORIZED' and ok_of(v[5]) and v[6] == 'Menu,Venue')

# snapshot, version, notifications
run('snapshot: hosts, active members only, my role and capabilities',
    [(H, "public.get_event_project('pj_main')"), (F, "public.get_event_project('pj_main')"), (O, "public.get_event_project('pj_main')")],
    lambda v: len(j(v[0])['hosts']) == 2 and len(j(v[0])['members']) == 6 and j(v[0])['me']['role'] == 'helper'
    and j(v[0])['is_host'] is False and j(v[1])['me']['cap_money'] is True and j(v[1])['me']['cap_checkin'] is True
    and j(v[2])['is_host'] is True and j(v[2])['me'] is None and len(j(v[0])['posts']) == 6 and j(v[0])['change_requests'] == []
    and len(j(v[2])['change_requests']) == 1)
run('version: unchanged answers are tiny; any write bumps the version',
    [(H, "(public.get_event_project('pj_main') ->> 'version')"),
     (H, "public.get_event_project('pj_main', (SELECT version FROM public.event_projects WHERE event_id = 'pj_main'))"),
     (H, f"public.project_set_task_status('{T_HELP_VENUE}', 'doing')"),
     (H, "public.get_event_project('pj_main', 1)")],
    lambda v: j(v[1]) == {'success': True, 'unchanged': True, 'version': int(v[0])} and ok_of(v[2]) and j(v[3])['unchanged'] is False)
run('blocked alerts both Host accounts at once, never the person who blocked it',
    [(H, f"public.project_set_task_status('{T_HELP_VENUE}', 'blocked')"),
     ('admin', "(SELECT string_agg(recipient_id::text, ',' ORDER BY recipient_id) FROM public.notifications WHERE kind = 'project_blocked')"),
     (O, f"public.project_set_task_status('{T_FIN_MENU}', 'blocked')"),
     ('admin', f"(SELECT count(*) FROM public.notifications WHERE kind = 'project_blocked' AND recipient_id = '{O}')")],
    lambda v: ok_of(v[0]) and v[1] == f'{O},{S}' and ok_of(v[2]) and v[3] == '1')

# topics
run('decide: the leading option wins (ties go to the first), the proposal resolves, the decision is locked',
    [('admin', f"!INSERT INTO public.event_project_post_votes (post_id, user_id, option_index) VALUES ('{P_PROP}', '{F}', 1), ('{P_PROP}', '{H}', 1), ('{P_PROP}', '{O}', 0)"),
     (LD, f"public.project_edit_post('{P_PROP}', 'Changed title', '')"),
     (M, f"public.project_decide_proposal('{P_PROP}')"),
     ('admin', f"(SELECT state FROM public.event_project_posts WHERE id = '{P_PROP}')"),
     (H, f"public.project_vote('{P_PROP}', 0)")],
    lambda v: err_of(v[1]) == 'ALREADY_ANSWERED' and ok_of(v[2]) and j(v[2])['decision']['title'] == 'Mushroom'
    and j(v[2])['decision']['state'] == 'locked' and v[3] == 'resolved' and err_of(v[4]) == 'NOT_OPEN')
run('vote toggles: the same option again takes the vote back',
    [(H, f"public.project_vote('{P_PROP}', 1)"), (H, f"public.project_vote('{P_PROP}', 1)"), (H, f"public.project_vote('{P_PROP}', 7)")],
    lambda v: j(v[0])['my_vote'] == 1 and j(v[1])['my_vote'] is None and err_of(v[2]) == 'INVALID_VALUE')
run('questions go to one other person in the project',
    [(H, f"public.project_create_post('pj_main', 'question', '{L_MENU}', 'Asking myself', '', NULL, '{H}')"),
     (H, f"public.project_create_post('pj_main', 'question', '{L_MENU}', 'Asking an outsider', '', NULL, '{OUT}')"),
     (H, f"public.project_create_post('pj_main', 'proposal', '{L_MENU}', 'One option only', '', ARRAY['A'])")],
    lambda v: err_of(v[0]) == 'ADDRESSEE_INVALID' and err_of(v[1]) == 'ADDRESSEE_INVALID' and err_of(v[2]) == 'NOT_AUTHORIZED')

# proposals of structure
run('proposals: decline needs a reason; approve applies the change',
    [(O, f"public.project_review_change('{R1}', false, '')"), (O, f"public.project_review_change('{R1}', true, NULL)"),
     ('admin', "(SELECT count(*) FROM public.event_project_lanes WHERE event_id = 'pj_main' AND name = 'Marketing' AND archived_at IS NULL)"),
     (O, f"public.project_review_change('{R1}', true, NULL)")],
    lambda v: err_of(v[0]) == 'REASON_REQUIRED' and ok_of(v[1]) and v[2] == '1' and err_of(v[3]) == 'NOT_PENDING')
run('proposals: a Manager cannot propose an unsafe link; a good link goes live only when the Host approves',
    [(M, "public.project_propose_change('pj_main', 'channel_add', NULL, '{\"channel\": {\"url\": \"javascript:alert(1)\"}}', 'Our call')"),
     (M, "public.project_propose_change('pj_main', 'channel_add', NULL, '{\"channel\": {\"url\": \"https://meet.google.com/abc-defg-hij\", \"primary\": true}}', 'Our call')"),
     ('admin', "(SELECT jsonb_array_length(channels) FROM public.event_projects WHERE event_id = 'pj_main')"),
     ('admin', "set_config('pj.req', (SELECT id::text FROM public.event_project_change_requests WHERE kind = 'channel_add'), true)"),
     (O, "public.project_review_change(current_setting('pj.req')::uuid, true, NULL)"),
     ('admin', "(SELECT channels -> 0 ->> 'platform' FROM public.event_projects WHERE event_id = 'pj_main')"),
     ('admin', "(SELECT count(*) FROM public.event_project_log WHERE action = 'channels.set' AND detail::text LIKE '%meet.google.com%')")],
    lambda v: err_of(v[0]) == 'CHANNELS_INVALID' and ok_of(v[1]) and v[2] == '0' and ok_of(v[4]) and v[5] == 'meet' and v[6] == '0')
run('channels: the Host saves a list; a bad list is refused whole',
    [(O, "public.project_set_channels('pj_main', '[{\"url\": \"https://zalo.me/g/x\", \"label\": \"Nhóm bếp\"}, {\"url\": \"http://zoom.us/j/1\"}]')"),
     (O, "public.project_set_channels('pj_main', '[{\"url\": \"https://zalo.me/g/x\", \"label\": \"Nhóm bếp\"}]')")],
    lambda v: err_of(v[0]) == 'CHANNELS_INVALID' and j(v[1])['channels'][0]['label'] == 'Nhóm bếp')

# run-of-show time rules
EV_START = "(((current_date + 11) + time '19:00') AT TIME ZONE 'Asia/Ho_Chi_Minh')"
run('run-of-show: 10-minute minimum, inside [start - 12h, start + 24h], ticks use the server clock, end moves with late items',
    [(M, f"public.project_upsert_ros_item('pj_main', NULL, 'Too short', NULL, {EV_START}, {EV_START} + interval '5 minutes')"),
     (M, f"public.project_upsert_ros_item('pj_main', NULL, 'Way too early', NULL, {EV_START} - interval '13 hours', {EV_START} - interval '12 hours')"),
     ('admin', "public.project_event_end('pj_main')::text"),
     (M, f"public.project_upsert_ros_item('pj_main', NULL, 'After midnight', NULL, {EV_START} + interval '5 hours', {EV_START} + interval '6 hours')"),
     ('admin', "(public.project_event_end('pj_main') > ((current_date + 12)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'))::text"),
     (H, f"public.project_tick_ros_item('{ROS_MAIN}', true)"),
     ('admin', f"(SELECT (done_at BETWEEN now() - interval '1 minute' AND now() + interval '1 minute')::text FROM public.event_project_ros_items WHERE id = '{ROS_MAIN}')"),
     (H, f"public.project_upsert_ros_item('pj_main', NULL, 'Helper edit', NULL, {EV_START}, {EV_START} + interval '30 minutes')")],
    lambda v: err_of(v[0]) == 'TIME_INVALID' and err_of(v[1]) == 'TIME_OUTSIDE_EVENT' and ok_of(v[3]) and v[4] == 'true'
    and ok_of(v[5]) and v[6] == 'true' and err_of(v[7]) == 'NOT_AUTHORIZED')
run('removing a member unassigns their open tasks and ends their access',
    [(O, f"public.project_remove_member('{MEMBER_ID[H]}', 'Left the team')"),
     ('admin', f"(SELECT assignee_id IS NULL FROM public.event_project_tasks WHERE id = '{T_HELP_VENUE}')::text"),
     (H, "public.get_event_project('pj_main')")],
    lambda v: ok_of(v[0]) and v[1] == 'true' and err_of(v[2]) == 'NOT_AUTHORIZED')
run('read-only: a past project refuses writes but stays readable and listed',
    [(O, f"public.project_add_lane('pj_past', 'Late lane')"), (H, "public.get_event_project('pj_past')"), (H, "public.get_my_event_projects()")],
    lambda v: err_of(v[0]) == 'READ_ONLY' and j(v[1])['project']['read_only'] is True
    and {p['event_id']: p['read_only'] for p in j(v[2])['projects']} == {'pj_main': False, 'pj_past': True})

# the iOS/web fixture tests/fixtures/project-snapshot.json must have exactly the keys the server returns
SNAP_FX = json.load(open(os.path.join(ROOT, 'tests/fixtures/project-snapshot.json')))['snapshot']
res, _ = transaction([(O, "public.get_event_project('pj_main')")])
real = j(res.get(0)) or {}
def shape(d):
    return {k: (sorted(v[0].keys()) if isinstance(v, list) and v and isinstance(v[0], dict) else sorted(v.keys()) if isinstance(v, dict) else None)
            for k, v in d.items()}
real_shape, fx_shape = shape(real), shape(SNAP_FX)
check('project-snapshot.json has the same keys as get_event_project (top level and every nested row)',
      sorted(real_shape) == sorted(fx_shape) and all(real_shape[k] == fx_shape[k] for k in real_shape if real_shape[k] and fx_shape.get(k)),
      str({k: (real_shape.get(k), fx_shape.get(k)) for k in set(real_shape) | set(fx_shape) if real_shape.get(k) != fx_shape.get(k)}))

# migration hygiene
res, err = transaction([('admin', "1")], setup=open(MIG).read() + '\n')
check('210 applies twice without error (idempotent)', res.get(0) == '1' and 'ERROR' not in err, err[:300])
res, err = transaction([('admin', "(SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name LIKE 'event_project%')"),
                        ('admin', "(SELECT count(*) FROM pg_proc WHERE proname LIKE 'project\\_%')"),
                        ('admin', "(SELECT count(*) FROM public.app_feature_flag_defs WHERE key = 'event_project_hub')")],
                       # Rollbacks run newest first: 212's and 211's (safe even where they were never applied), then 210's.
                       setup=open(ROLLBACK_212).read() + '\n' + open(ROLLBACK_211).read() + '\n' + open(ROLLBACK).read() + '\n')
check('the rollback removes every table, function and switch of 210', [res.get(i) for i in range(3)] == ['0', '0', '0'] and 'ERROR' not in err,
      f'{res} {err[:300]}')
src = open(MIG).read()
host_fn = re.search(r'CREATE OR REPLACE FUNCTION public\.project_host_ids.*?\$\$;', src, re.S).group(0)
code = '\n'.join(l for l in src.replace(host_fn, '').splitlines() if not l.strip().startswith('--'))
bad = re.findall(r'.{0,40}\bo\.(?:owner_id|user_id)\b.{0,10}|.{0,40}organizers\b[^;]*\b(?:owner_id|user_id)\b.{0,10}', code)
check('organizers.owner_id / user_id appear only inside project_host_ids()', not bad, str(bad[:3]))

print(f'\n{PASSES} passed, {len(FAILS)} failed')
sys.exit(1 if FAILS else 0)
