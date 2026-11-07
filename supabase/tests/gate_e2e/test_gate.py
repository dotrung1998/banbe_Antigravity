#!/usr/bin/env python3
"""
Assertion-based gate tests against a REAL local Supabase stack
(supabase/postgres + GoTrue + PostgREST + storage-api, the repo's full
migration chain applied). Real sign-ups, real sessions, real JWTs (with real
`session_id` and `amr` claims) sent through PostgREST — nothing stubbed.

Run:  ./stack_up.sh && ./apply_migrations.sh && ./test_gate.py
Exit code 0 only if every assertion holds. No SMS is sent (GoTrue test OTPs).
"""
import base64, hashlib, hmac, json, re, subprocess, sys, time, urllib.request, urllib.error, uuid

SECRET = b"super-secret-jwt-token-with-at-least-32-characters-long"
AUTH = "http://localhost:54399"
REST = "http://localhost:54300"
MAIL = "http://localhost:54325"
TEST_PHONE_A, TEST_PHONE_B, OTP = "+14155550101", "+14155550102", "123456"

FAILS, PASSES = [], 0


def check(name, cond, detail=""):
    global PASSES
    if cond:
        PASSES += 1
        print(f"  ok   {name}")
    else:
        FAILS.append(name)
        print(f"  FAIL {name} {detail}")


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def mint(role):
    h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    p = b64(json.dumps({"role": role, "iss": "supabase-local", "exp": int(time.time()) + 3600}).encode())
    s = b64(hmac.new(SECRET, f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{s}"


ANON, SERVICE = mint("anon"), mint("service_role")


def http(method, url, body=None, token=None, apikey=None):
    h = {"Content-Type": "application/json"}
    if apikey:
        h["apikey"] = apikey
    if token:
        h["Authorization"] = "Bearer " + token
    r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as f:
            raw = f.read()
            try:
                return f.status, (json.loads(raw) if raw else None)
            except ValueError:
                return f.status, raw.decode(errors="replace")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode(errors="replace")


def sql(q):
    out = subprocess.run(["docker", "exec", "-i", "g-db", "psql", "-U", "supabase_admin", "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1"],
                         input=q, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr)
    return out.stdout.strip(), out.stderr


def rest(method, path, token, body=None):
    return http(method, REST + path, body, token=token, apikey=token)


def rpc(name, token, body=None):
    return rest("POST", f"/rpc/{name}", token, body or {})


# ------------------------------------------------------------------ auth helpers
def signup(email, password="Passw0rd!x"):
    code, j = http("POST", AUTH + "/signup", {"email": email, "password": password}, apikey=ANON)
    if code in (200, 201):
        return j["user"]["id"]
    # re-runs: the three fixed seed emails may already exist
    uid = sql(f"select id from auth.users where lower(email)=lower('{email}')")[0]
    assert uid, (code, j)
    return uid


def password_login(email, password="Passw0rd!x"):
    code, j = http("POST", AUTH + "/token?grant_type=password", {"email": email, "password": password}, apikey=ANON)
    assert code == 200, (code, j)
    return j


def email_code_login(email):
    time.sleep(1.5)  # GoTrue throttles repeat OTP requests per user (configured to 1s here)
    http("DELETE", MAIL + "/api/v1/messages")  # clean inbox
    code, _ = http("POST", AUTH + "/otp", {"email": email, "create_user": False}, apikey=ANON)
    assert code == 200, code
    for _ in range(20):
        time.sleep(0.5)
        _, lst = http("GET", MAIL + "/api/v1/messages")
        if lst and lst.get("messages"):
            mid = lst["messages"][0]["ID"]
            _, msg = http("GET", MAIL + f"/api/v1/message/{mid}")
            m = re.search(r"\b(\d{6})\b", (msg.get("Text") or "") + (msg.get("HTML") or ""))
            if m:
                break
    else:
        raise AssertionError("no email OTP arrived")
    code, j = http("POST", AUTH + "/verify", {"type": "email", "email": email, "token": m.group(1)}, apikey=ANON)
    assert code == 200, (code, j)
    return j


def jwt_claims(tok):
    p = tok.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(p + "=" * (-len(p) % 4)))


def status(tok):
    c, j = rpc("account_gate_status", tok)
    assert c == 200, (c, j)
    return j


def is_gate_403(resp):
    code, body = resp
    return code == 403 and "ACCOUNT_GATE_REQUIRED" in json.dumps(body)


DOB = {"a": "1998-06-15"}


def serve_templates():
    """GoTrue fetches this email template over HTTP: a 6-digit code, like the app's own email-code mail."""
    import http.server, threading

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = b"<p>Your code: {{ .Token }}</p>"
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers(); self.wfile.write(body)

        def log_message(self, *a):
            pass

    srv = http.server.ThreadingHTTPServer(("0.0.0.0", 54390), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()


def main():
    serve_templates()
    sfx = uuid.uuid4().hex[:6]
    print("== setup")
    ids = {}
    emails = {k: f"{k}.{sfx}@example.com" for k in ["new", "seeded", "legacy", "host", "guest"]}
    for k, e in emails.items():
        ids[k] = signup(e)

    # ---------------------------------------------------------------- anon browsing
    print("== anon public browsing is preserved")
    c, _ = rest("GET", "/events?select=id&limit=1", ANON)
    check("anon can read the public catalogue (events)", c == 200, str(c))
    c, _ = rest("GET", "/organizers?select=id&limit=1", ANON)
    check("anon can read organizers", c == 200, str(c))
    c, _ = rest("GET", "/profiles?select=id&limit=1", ANON)
    check("anon is not newly broken or newly privileged on profiles (200 or 401/403, never 5xx)", c < 500, str(c))

    # ---------------------------------------------------------------- new registration, gated
    print("== NEW registration (not in grandfather cohort): gated until phone + DOB")
    tn = password_login(emails["new"])["access_token"]
    cl = jwt_claims(tn)
    check("real JWT carries session_id and a password amr", "session_id" in cl and any(a.get("method") == "password" for a in cl.get("amr", [])), str(cl.get("amr")))
    st = status(tn)
    check("status: phone + DOB enrollment required, not ready", st["phone_required"] and st["dob_enrollment_required"] and not st["ready"], str(st))
    check("gate RPCs stay reachable while gated (account_gate_status 200)", True)
    check("gated: table read blocked (profiles)", is_gate_403(rest("GET", "/profiles?select=id", tn)))
    check("gated: table read blocked (bookings)", is_gate_403(rest("GET", "/bookings?select=id", tn)))
    check("gated: public catalogue blocked for a signed-in gated session", is_gate_403(rest("GET", "/events?select=id&limit=1", tn)))
    check("gated: SECURITY DEFINER rpc hold_seats blocked BEFORE it runs", is_gate_403(rpc("hold_seats", tn, {"p_event": "x", "p_qty": 1})))
    check("gated: SECURITY DEFINER rpc confirm_payment blocked", is_gate_403(rpc("confirm_payment", tn, {"p_booking": str(uuid.uuid4())})))
    check("gated: SECURITY DEFINER rpc check_in_guest blocked", is_gate_403(rpc("check_in_guest", tn, {"p_reservation_id": str(uuid.uuid4())})))
    check("gated: promo rpc next_promo_recipient blocked", is_gate_403(rpc("next_promo_recipient", tn, {"p_event_id": "x"})))
    check("gated: get_checkin_guest_info blocked", is_gate_403(rpc("get_checkin_guest_info", tn, {"p_booking_id": str(uuid.uuid4())})))

    print("== generic sweep: EVERY authenticated-executable SECURITY DEFINER function")
    out, err = sql(f"""
DO $$
DECLARE r record; total int := 0; bypass int := 0; allow text[] := ARRAY['account_gate_status','account_gate_ok','set_date_of_birth','confirm_date_of_birth'];
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','sub','{ids['new']}')::text, true);
  FOR r IN SELECT DISTINCT p.proname FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef
            AND has_function_privilege('authenticated', p.oid, 'EXECUTE') AND NOT (p.proname = ANY (allow)) LOOP
    total := total + 1;
    PERFORM set_config('request.path', '/rpc/' || r.proname, true);
    BEGIN PERFORM public.gate_pre_request(); bypass := bypass + 1; RAISE WARNING 'BYPASS %', r.proname;
    EXCEPTION WHEN SQLSTATE 'PT403' THEN NULL; END;
  END LOOP;
  RAISE NOTICE 'SWEEP total=% bypass=%', total, bypass;
END $$;""")
    m = re.search(r"SWEEP total=(\d+) bypass=(\d+)", err)
    check("sweep covered >100 functions", bool(m) and int(m.group(1)) > 100, err[-200:])
    check("sweep: zero SECURITY DEFINER functions reachable by a gated session", bool(m) and m.group(2) == "0", err[-400:])
    out, err = sql(f"""
DO $$ DECLARE n int; BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','sub','{ids['new']}')::text, true);
  FOREACH n IN ARRAY ARRAY[1] LOOP NULL; END LOOP;
  PERFORM set_config('request.path', '/rpc/account_gate_status', true); PERFORM public.gate_pre_request();
  PERFORM set_config('request.path', '/rpc/set_date_of_birth', true); PERFORM public.gate_pre_request();
  PERFORM set_config('request.path', '/rpc/confirm_date_of_birth', true); PERFORM public.gate_pre_request();
  RAISE NOTICE 'ALLOW_OK';
END $$;""")
    check("sweep: the three enrollment/confirm RPCs are the only exemptions", "ALLOW_OK" in err, err[-200:])

    print("== storage objects are gated too (Storage API goes straight to Postgres)")
    sql("insert into storage.objects(bucket_id,name,owner) select 'event-photos','gate-test-"+sfx+".txt',null where exists (select 1 from storage.buckets where id='event-photos') on conflict do nothing;")
    out, _ = sql(f"""
begin; set local role authenticated;
select set_config('request.jwt.claims', json_build_object('role','authenticated','sub','{ids['new']}')::text, true);
select count(*) from storage.objects where name='gate-test-{sfx}.txt'; rollback;""")
    nums = [l for l in out.splitlines() if l.strip().isdigit()]
    gated_rows = int(nums[-1]) if nums else -1
    exists = sql(f"select count(*) from storage.objects where name='gate-test-{sfx}.txt'")[0]
    check("control: the object exists (superuser sees it)", exists == "1", exists)
    check("gated session sees 0 storage objects (restrictive policy)", gated_rows == 0, out)

    # ---------------------------------------------------------------- phone: same user, no duplicates
    print("== phone verification binds to the SAME user (real GoTrue phone_change, test OTP, no SMS sent)")
    sess = password_login(emails["new"])
    c, j = http("PUT", AUTH + "/user", {"phone": TEST_PHONE_A}, token=sess["access_token"], apikey=ANON)
    check("update(user: phone) accepted (OTP created by Auth, not by us)", c == 200, f"{c} {j}")
    c, j = http("POST", AUTH + "/verify", {"type": "phone_change", "phone": TEST_PHONE_A, "token": "000000"}, apikey=ANON)
    check("wrong code does NOT verify the phone", c >= 400, f"{c}")
    c, j = http("POST", AUTH + "/verify", {"type": "phone_change", "phone": TEST_PHONE_A, "token": OTP}, apikey=ANON)
    check("correct code verifies", c == 200, f"{c} {j}")
    user_after = j["user"] if isinstance(j, dict) and "user" in j else {}
    check("verified phone is on the SAME user id", user_after.get("id") == ids["new"], str(user_after.get("id")))
    out, _ = sql(f"select count(*) from auth.users where phone is not null and phone <> ''")
    check("exactly one auth user holds the phone", sql(f"select count(*) from auth.users where phone = '{TEST_PHONE_A.lstrip('+')}'")[0] == "1")
    check("still exactly the originally created accounts (no duplicate accounts)", sql(f"select count(*) from auth.users where email like '%.{sfx}@example.com'")[0] == "5")
    sess2 = password_login(emails["new"])
    st = status(sess2["access_token"])
    check("phone now verified; DOB still required -> still gated", st["phone_verified"] and not st["phone_required"] and st["dob_enrollment_required"] and not st["ready"], str(st))
    # another user can't take the same phone
    tg = password_login(emails["guest"])["access_token"]
    c, j = http("PUT", AUTH + "/user", {"phone": TEST_PHONE_A}, token=tg, apikey=ANON)
    check("a second account cannot claim the same phone (phone_exists)", c >= 400 and "phone" in json.dumps(j).lower(), f"{c} {j}")

    print("== enrollment DOB rules (server side)")
    tn = sess2["access_token"]
    check("future DOB refused", rpc("set_date_of_birth", tn, {"p_dob": "2999-01-01"})[1].get("error") == "DOB_IN_FUTURE")
    check("pre-1900 DOB refused", rpc("set_date_of_birth", tn, {"p_dob": "1899-12-31"})[1].get("error") == "INVALID_DOB")
    c, j = rpc("set_date_of_birth", tn, {"p_dob": "1999-02-29"})
    check("impossible calendar date refused by the database", c >= 400, f"{c} {j}")
    check("leap-day DOB accepted", rpc("set_date_of_birth", tn, {"p_dob": "2000-02-29"})[1].get("success") is True)
    check("DOB can't be overwritten", rpc("set_date_of_birth", tn, {"p_dob": "1990-01-01"})[1].get("error") == "ALREADY_SET")
    check("enrollment complete -> ready, data reachable", status(tn)["ready"] and rest("GET", "/profiles?select=id&limit=1", tn)[0] == 200)
    check("no client can read the DOB table", rest("GET", "/user_private_dob?select=*", tn)[0] in (401, 403, 404))
    check("no RPC returns the stored DOB to its owner", "date_of_birth" not in json.dumps(rpc("account_gate_status", tn)[1]))

    # ---------------------------------------------------------------- seeded/legacy
    print("== DOB confirmation: email-code sessions only; password / OAuth exempt")
    sid_seeded = ids["seeded"]
    sql(f"insert into public.account_phone_grandfathered(user_id,cohort) values ('{sid_seeded}','test') on conflict do nothing;"
        f"insert into public.user_private_dob(user_id,date_of_birth,source) values ('{sid_seeded}','1998-06-15','seed_test') on conflict do nothing;")
    tp = password_login(emails["seeded"])["access_token"]
    check("password session of a user WITH a DOB is ready (no DOB prompt)", status(tp)["ready"] and rest("GET", "/profiles?select=id&limit=1", tp)[0] == 200)
    ote = email_code_login(emails["seeded"])
    to = ote["access_token"]
    amr = [a.get("method") for a in jwt_claims(to).get("amr", [])]
    check("email-code session is an otp session", "otp" in amr and "password" not in amr, str(amr))
    st = status(to)
    check("email-code session: DOB confirmation required, not ready", st["dob_confirmation_required"] and not st["ready"], str(st))
    check("email-code session is blocked from data until confirmed", is_gate_403(rest("GET", "/profiles?select=id", to)))
    check("email-code session blocked from SECURITY DEFINER rpc until confirmed", is_gate_403(rpc("hold_seats", to, {"p_event": "x", "p_qty": 1})))
    r = rpc("confirm_date_of_birth", to, {"p_dob": "1998-06-14"})[1]
    check("wrong DOB -> INCORRECT with attempts_left, no DOB in response", r.get("error") == "INCORRECT" and "1998" not in json.dumps(r), str(r))
    r = rpc("confirm_date_of_birth", to, {"p_dob": "1998-06-15"})[1]
    check("correct DOB confirms the session", r.get("success") is True, str(r))
    check("after confirming: ready and data reachable", status(to)["ready"] and rest("GET", "/profiles?select=id&limit=1", to)[0] == 200)
    code, rf = http("POST", AUTH + "/token?grant_type=refresh_token", {"refresh_token": ote["refresh_token"]}, apikey=ANON)
    check("refresh keeps the SAME session and stays confirmed (no re-prompt on token refresh)",
          code == 200 and jwt_claims(rf["access_token"])["session_id"] == jwt_claims(to)["session_id"] and status(rf["access_token"])["ready"], str(code))
    to2 = email_code_login(emails["seeded"])["access_token"]
    check("a NEW email-code login (new session) must confirm again", status(to2)["dob_confirmation_required"] and not status(to2)["ready"])
    for i in range(4):
        rpc("confirm_date_of_birth", to2, {"p_dob": "2001-01-0" + str(i + 1)})
    r = rpc("confirm_date_of_birth", to2, {"p_dob": "2001-02-02"})[1]
    check("5th wrong attempt locks confirmation", r.get("error") == "LOCKED", str(r))
    r = rpc("confirm_date_of_birth", to2, {"p_dob": "1998-06-15"})[1]
    check("even the correct DOB is refused while locked", r.get("error") == "LOCKED", str(r))
    check("no bypass: password session of the same user is still fine (exemption is by login method)", status(password_login(emails["seeded"])["access_token"])["ready"])

    print("== legacy user (grandfathered, no DOB): keeps access; optional phone verification works")
    sql(f"insert into public.account_phone_grandfathered(user_id,cohort) values ('{ids['legacy']}','test') on conflict do nothing;")
    tl = email_code_login(emails["legacy"])["access_token"]
    st = status(tl)
    check("legacy user (no DOB, no phone) is ready via email code", st["ready"] and not st["phone_verified"], str(st))
    check("legacy user reaches data", rest("GET", "/profiles?select=id&limit=1", tl)[0] == 200)
    c, _ = http("PUT", AUTH + "/user", {"phone": TEST_PHONE_B}, token=tl, apikey=ANON)
    c2, j2 = http("POST", AUTH + "/verify", {"type": "phone_change", "phone": TEST_PHONE_B, "token": OTP}, apikey=ANON)
    check("legacy user can OPT IN to phone verification (same user id)", c == 200 and c2 == 200 and j2["user"]["id"] == ids["legacy"], f"{c} {c2}")
    st = status(password_login(emails["legacy"])["access_token"])
    check("after opting in: phone_verified true and still ready (exemption intact)", st["phone_verified"] and st["ready"], str(st))

    # ---------------------------------------------------------------- 123 seed behaviour
    print("== migration 123 cohort + seed behaviour on real auth.users")
    sql("delete from public.user_private_dob where source in ('seed_123_t'); delete from public.account_gate_migrations where name='123_cohort_and_seed';")
    # fabricate the three approved emails + a conflict, run ONLY the migration's DO block
    seed_users = {"dotrung1998@gmail.com": "1998-06-15", "doqanh0609@gmail.com": "2006-09-16", "banbetestadmin@gmail.com": "1998-06-15"}
    existing = {}
    for e in ["dotrung1998@gmail.com", "banbetestadmin@gmail.com"]:
        existing[e] = signup(e)
    sql(f"insert into public.user_private_dob(user_id,date_of_birth,source) values ('{existing['banbetestadmin@gmail.com']}','1990-01-01','pre_existing') on conflict (user_id) do update set date_of_birth='1990-01-01', source='pre_existing';"
        f"delete from public.user_private_dob where user_id='{existing['dotrung1998@gmail.com']}';")
    mig = open("../../migrations/20261104000123_123_phone_dob_gate_and_promo_consent.sql").read()
    block = re.search(r"(DO \$\$\nDECLARE\n  rec record;.*?\nEND;\n\$\$;)", mig, re.S).group(1)
    _, err = sql(block)
    d1 = sql(f"select date_of_birth::text, source from public.user_private_dob where user_id='{existing['dotrung1998@gmail.com']}'")[0]
    d2 = sql(f"select date_of_birth::text, source from public.user_private_dob where user_id='{existing['banbetestadmin@gmail.com']}'")[0]
    check("seed: dotrung1998 stored 1998-06-15", d1.startswith("1998-06-15|seed_123"), d1)
    check("seed: conflicting existing DOB NOT overwritten (banbetestadmin keeps 1990-01-01)", d2.startswith("1990-01-01|pre_existing"), d2)
    check("seed: conflict is reported as a WARNING", "CONFLICT" in err, err[-300:])
    check("seed: missing doqanh0609@gmail.com skipped with a warning, no user created",
          "no auth user for doqanh0609@gmail.com" in err and sql("select count(*) from auth.users where lower(email)='doqanh0609@gmail.com'")[0] == "0")
    n_before = sql("select count(*) from public.user_private_dob")[0]
    _, err2 = sql(block)
    check("seed: re-running is a no-op (idempotent)", sql("select count(*) from public.user_private_dob")[0] == n_before and "already applied" in err2, err2[-200:])
    check("seed: cohort rows never mark a phone verified", sql("select count(*) from auth.users u join public.account_phone_grandfathered g on g.user_id=u.id where u.phone_confirmed_at is not null and u.email like '%@gmail.com'")[0] == "0")

    # ---------------------------------------------------------------- promo retry semantics
    print("== promo: cancelled/failed can retry; sent is final; stale 'presented' expires")
    host, guest = ids["host"], ids["guest"]
    org, ev = "o" + sfx, "e" + sfx
    sql(f"""
insert into public.account_phone_grandfathered(user_id,cohort) values ('{host}','test'),('{guest}','test') on conflict do nothing;
insert into public.organizers(id, owner_id, name) values ('{org}','{host}','Promo Org');
insert into public.events(id, organizer_id, name) values ('{ev}','{org}','Promo Event');
insert into public.follows(user_id, organizer_id) values ('{guest}','{org}');
update auth.users set phone='14155550999', phone_confirmed_at=now() where id='{guest}';
insert into public.host_promo_consent(user_id, consented, consented_at) values ('{guest}', true, now()) on conflict (user_id) do update set consented=true;""")
    th = password_login(emails["host"])["access_token"]
    tg = password_login(emails["guest"])["access_token"]
    check("consent default is OFF for everyone (no row = off)", rpc("get_host_promo_consent", th)[1].get("consented") is False)
    r1 = rpc("next_promo_recipient", th, {"p_event_id": ev})[1]
    check("host gets exactly one recipient, by name only (no phone)", r1["recipient"]["id"] == guest and "phone" not in json.dumps(r1))
    b1 = rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1]
    check("begin returns the phone only now, after rechecks", b1.get("success") and b1["phone"].startswith("+1415"), str(b1))
    check("a second begin while one is in progress is refused", rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1].get("error") == "ALREADY_PROMPTED")
    rpc("finish_promo_compose", th, {"p_log_id": b1["log_id"], "p_result": "cancelled"})
    r2 = rpc("next_promo_recipient", th, {"p_event_id": ev})[1]
    check("after CANCEL the recipient is NOT consumed: offered again", r2["recipient"] and r2["recipient"]["id"] == guest, str(r2))
    b2 = rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1]
    check("retry after cancel works", b2.get("success"), str(b2))
    rpc("finish_promo_compose", th, {"p_log_id": b2["log_id"], "p_result": "failed"})
    b3 = rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1]
    check("retry after FAIL works (attempt 3)", b3.get("success"), str(b3))
    rpc("finish_promo_compose", th, {"p_log_id": b3["log_id"], "p_result": "sent"})
    check("after SENT the recipient is done for this event", rpc("next_promo_recipient", th, {"p_event_id": ev})[1]["recipient"] is None)
    rpc("finish_promo_compose", th, {"p_log_id": b3["log_id"], "p_result": "cancelled"})
    check("a recorded SENT cannot be flipped back to re-enable a resend",
          sql(f"select result from public.host_promo_compose_log where id='{b3['log_id']}'")[0] == "sent")
    check("begin after SENT is refused", rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1].get("error") == "ALREADY_PROMPTED")
    # stale presented
    sql(f"delete from public.host_promo_compose_log where event_id='{ev}';")
    b4 = rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1]
    sql(f"update public.host_promo_compose_log set created_at = now() - interval '20 minutes' where id='{b4['log_id']}';")
    b5 = rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1]
    check("an abandoned 'presented' attempt expires after 15 min and can be retried", b5.get("success"), str(b5))
    check("withdrawing consent blocks compose immediately", (rpc("set_host_promo_consent", tg, {"p_enabled": False}), rpc("begin_promo_compose", th, {"p_event_id": ev, "p_recipient_id": guest})[1].get("error"))[1] == "NOT_ELIGIBLE")

    # ---------------------------------------------------------------- kill switch
    print("== kill switch")
    sql("update public.account_gate_config set enabled=false where key='api_enforcement';")
    tn_now = password_login(emails["new"])["access_token"]
    # 'new' completed enrollment above; use 'guest2' style: a fresh gated user
    gx = signup(f"gated2.{sfx}@example.com")
    tgx = password_login(f"gated2.{sfx}@example.com")["access_token"]
    c, _ = rpc("hold_seats", tgx, {"p_event": "x", "p_qty": 1})
    check("kill switch OFF: the API hook stops blocking (so it can be disabled safely)", c != 403, str(c))
    sql("update public.account_gate_config set enabled=true where key='api_enforcement';")
    check("kill switch back ON: blocked again", is_gate_403(rpc("hold_seats", tgx, {"p_event": "x", "p_qty": 1})))

    print(f"\n{PASSES} passed, {len(FAILS)} failed")
    if FAILS:
        for f in FAILS:
            print("  FAILED:", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
