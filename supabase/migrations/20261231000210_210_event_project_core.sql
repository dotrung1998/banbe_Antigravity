-- 210 — Event Project Hub core (note 76, phase 2): a private team workspace per event.
--
-- Tables (every write goes through a SECURITY DEFINER RPC below; authenticated may only SELECT, under RLS):
--   event_projects                one per event, opt-in (start_event_project); version bumps on every write
--   event_project_lanes           work areas, max 10 active, archived instead of deleted
--   event_project_members         private working roles: manager ("Quản lý"), finance, lane_lead, helper
--   event_project_invites         opaque 22-char token + typed BB-XXXX code; role/lane live here, never in the link
--   event_project_invite_attempts failed peeks/redeems, for the 10-per-hour lock
--   event_project_change_requests a Manager proposes lane/channel changes; only the Host applies them
--   event_project_tasks / _posts / _post_votes / _post_replies / _post_seen / _ros_items
--   event_project_log             append-only project history (task history, decisions, trash, members)
--
-- The Host is never stored. project_host_ids() is the ONE place that says who the Host is: v1 = both organizer
-- accounts (owner_id and user_id), exactly like is_event_host(). Switching to owner_id only is a one-line change there,
-- and the SQL test suite proves nothing else in project code depends on user_id. Money and door RPCs are NOT touched
-- here; when delegation comes (212-214) they keep their own owner_id-or-user_id check and add delegates on top.
--
-- Limits match src/data/projectLimits.json (project_limits() below; the test compares them). Time: an event "ends" at
-- the later of midnight after event_date in events.tz and the last run-of-show end; the project is read-only 30 days
-- after that (purge at 90 days comes with the jobs migration 211).
--
-- Switches (all seeded OFF): event_project_hub (every RPC refuses while off), project_qr_invite (multi-use invites),
-- project_delegate_checkin / _payments / _refunds (defined now so admins see them; enforced from 212-214).
--
-- LOCAL HARNESS ONLY until the owner says otherwise: never pushed to production by this pass.
-- Rollback: supabase/rollbacks/20261231000210_210_revert_event_project_core.sql (kept OUT of migrations/).

-- ================================================================== switches
INSERT INTO public.app_feature_flag_defs (key, description, added_in) VALUES
  ('event_project_hub', 'Event Project Hub: private per-event team workspace (note 76)', '210'),
  ('project_qr_invite', 'Event Project Hub: QR and multi-use invites (up to 20 uses)', '210'),
  ('project_delegate_checkin', 'Event Project Hub: team members with check-in access may check guests in (needs 212)', '210'),
  ('project_delegate_payments', 'Event Project Hub: team members with money access may confirm payments (needs 213)', '210'),
  ('project_delegate_refunds', 'Event Project Hub: team members with money access may handle refunds (needs 214)', '210')
ON CONFLICT (key) DO NOTHING;
INSERT INTO public.app_feature_flags (key, enabled) VALUES
  ('event_project_hub', false), ('project_qr_invite', false), ('project_delegate_checkin', false),
  ('project_delegate_payments', false), ('project_delegate_refunds', false)
ON CONFLICT (key) DO NOTHING;

-- ================================================================== limits (= src/data/projectLimits.json)
CREATE OR REPLACE FUNCTION public.project_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'lanesMax', 10, 'laneNameMax', 24, 'changeWhyMax', 140, 'reasonMin', 3, 'reasonMax', 140,
    'taskTitleMin', 3, 'taskTitleMax', 60, 'postTitleMin', 3, 'postTitleMax', 80, 'postBodyMax', 280,
    'replyMax', 140, 'repliesMax', 10, 'proposalOptionsMin', 2, 'proposalOptionsMax', 4, 'proposalOptionMax', 40,
    'rosTitleMin', 2, 'rosTitleMax', 40, 'rosMinMinutes', 10, 'rosWindowBeforeStartHours', 12, 'rosWindowAfterStartHours', 24,
    'trashMax', 30, 'trashDays', 7, 'channelsMax', 5, 'channelLabelMax', 30, 'channelUrlMax', 300,
    'inviteHours', 48, 'inviteMaxUses', 20, 'grantDays', 7, 'readOnlyDays', 30, 'purgeDays', 90);
$$;
CREATE OR REPLACE FUNCTION public.project_limit(p_key text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$ SELECT (public.project_limits() ->> p_key)::int $$;

-- ================================================================== team channel links (= src/lib/projectChannels.js)
-- Same URL rule as sanitize_social_links (102:43). The host must BE the platform domain or a subdomain of it.
-- Returns the cleaned list, or NULL when anything is wrong (one bad entry rejects the whole list).
CREATE OR REPLACE FUNCTION public.project_channel_domains(p_platform text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_platform
    WHEN 'zoom' THEN ARRAY['zoom.us']
    WHEN 'meet' THEN ARRAY['meet.google.com']
    WHEN 'zalo' THEN ARRAY['zalo.me']
    WHEN 'messenger' THEN ARRAY['m.me', 'messenger.com']
    WHEN 'whatsapp' THEN ARRAY['chat.whatsapp.com', 'wa.me']
    WHEN 'telegram' THEN ARRAY['t.me']
    WHEN 'discord' THEN ARRAY['discord.gg', 'discord.com']
    WHEN 'teams' THEN ARRAY['teams.microsoft.com', 'teams.live.com']
    WHEN 'slack' THEN ARRAY['slack.com']
    WHEN 'link' THEN ARRAY[]::text[]
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.project_channel_name(p_platform text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_platform
    WHEN 'zoom' THEN 'Zoom' WHEN 'meet' THEN 'Google Meet' WHEN 'zalo' THEN 'Zalo' WHEN 'messenger' THEN 'Messenger'
    WHEN 'whatsapp' THEN 'WhatsApp' WHEN 'telegram' THEN 'Telegram' WHEN 'discord' THEN 'Discord'
    WHEN 'teams' THEN 'Microsoft Teams' WHEN 'slack' THEN 'Slack' ELSE '' END;
$$;

CREATE OR REPLACE FUNCTION public.project_host_on(p_host text, p_domains text[])
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT EXISTS (SELECT 1 FROM unnest(p_domains) d WHERE p_host = d OR right(p_host, length(d) + 1) = '.' || d);
$$;

CREATE OR REPLACE FUNCTION public.sanitize_project_channels(p_channels jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_item jsonb;
  v_url text; v_host text; v_platform text; v_label text; v_domains text[];
  v_primaries int := 0;
  v_seen text[] := ARRAY[]::text[];
  v_p text;
BEGIN
  IF p_channels IS NULL OR jsonb_typeof(p_channels) <> 'array' THEN RETURN NULL; END IF;
  IF jsonb_array_length(p_channels) > public.project_limit('channelsMax') THEN RETURN NULL; END IF;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_channels) LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN RETURN NULL; END IF;
    v_url := btrim(coalesce(v_item ->> 'url', ''), E' \t\r\n');
    IF v_url = '' OR length(v_url) > public.project_limit('channelUrlMax') OR v_url ~ '[[:space:][:cntrl:]]'
       OR v_url !~* '^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}(/.*)?(\?.*)?$' THEN
      RETURN NULL;
    END IF;
    v_host := lower(substring(v_url FROM '(?i)^https://([^/?#]+)'));
    v_platform := lower(btrim(coalesce(v_item ->> 'platform', '')));
    IF v_platform = '' THEN
      v_platform := 'link';
      FOREACH v_p IN ARRAY ARRAY['zoom', 'meet', 'zalo', 'messenger', 'whatsapp', 'telegram', 'discord', 'teams', 'slack'] LOOP
        IF public.project_host_on(v_host, public.project_channel_domains(v_p)) THEN v_platform := v_p; EXIT; END IF;
      END LOOP;
    END IF;
    v_domains := public.project_channel_domains(v_platform);
    IF v_domains IS NULL THEN RETURN NULL; END IF;
    IF cardinality(v_domains) > 0 AND NOT public.project_host_on(v_host, v_domains) THEN RETURN NULL; END IF;
    v_label := btrim(coalesce(v_item ->> 'label', ''), E' \t\r\n');
    IF v_label = '' THEN v_label := public.project_channel_name(v_platform); END IF;
    IF length(v_label) > public.project_limit('channelLabelMax') THEN RETURN NULL; END IF;
    IF lower(v_url) = ANY (v_seen) THEN RETURN NULL; END IF;
    v_seen := v_seen || lower(v_url);
    -- A missing "primary" means false (JSON -> on a missing key is NULL).
    IF coalesce(v_item -> 'primary' = 'true'::jsonb, false) THEN v_primaries := v_primaries + 1; END IF;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'platform', v_platform, 'label', v_label, 'url', v_url, 'primary', coalesce(v_item -> 'primary' = 'true'::jsonb, false)));
  END LOOP;
  IF v_primaries > 1 THEN RETURN NULL; END IF;
  RETURN v_out;
END;
$$;

-- ================================================================== tables
CREATE TABLE IF NOT EXISTS public.event_projects (
  event_id text PRIMARY KEY REFERENCES public.events(id) ON DELETE CASCADE,
  started_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  version bigint NOT NULL DEFAULT 1,
  channels jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (public.sanitize_project_channels(channels) IS NOT NULL),
  -- Used from 214: 'host' = a delegate requests, the Host approves; 'finance_alone' = Finance may refund alone.
  refund_approval text NOT NULL DEFAULT 'host' CHECK (refund_approval IN ('host', 'finance_alone'))
);

CREATE TABLE IF NOT EXISTS public.event_project_lanes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 24),
  position int NOT NULL DEFAULT 0,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz,
  archived_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  archive_reason text,
  CHECK (archived_at IS NULL OR length(btrim(coalesce(archive_reason, ''))) BETWEEN 3 AND 140)
);
CREATE UNIQUE INDEX IF NOT EXISTS event_project_lanes_active_name
  ON public.event_project_lanes (event_id, lower(btrim(name))) WHERE archived_at IS NULL;

CREATE TABLE IF NOT EXISTS public.event_project_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('manager', 'finance', 'lane_lead', 'helper')),
  lane_id uuid REFERENCES public.event_project_lanes(id) ON DELETE SET NULL,
  cap_money boolean NOT NULL DEFAULT false,
  cap_checkin boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
  -- NULL = the default (event end + 7 days); used from 212.
  grant_expires_at timestamptz,
  invited_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  removed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  UNIQUE (event_id, user_id)
);
CREATE INDEX IF NOT EXISTS event_project_members_user ON public.event_project_members (user_id) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.event_project_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE CHECK (token ~ '^[A-Za-z0-9_-]{22}$'),
  short_code text NOT NULL CHECK (short_code ~ '^BB-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}$'),
  role text NOT NULL CHECK (role IN ('manager', 'finance', 'lane_lead', 'helper')),
  lane_id uuid REFERENCES public.event_project_lanes(id) ON DELETE SET NULL,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  max_uses int NOT NULL DEFAULT 1 CHECK (max_uses BETWEEN 1 AND 20),
  uses int NOT NULL DEFAULT 0 CHECK (uses >= 0 AND uses <= max_uses),
  revoked_at timestamptz
);
-- A typed code is unique among invites that are not revoked (expired ones are purged daily by 211).
CREATE UNIQUE INDEX IF NOT EXISTS event_project_invites_live_code
  ON public.event_project_invites (short_code) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS public.event_project_invite_attempts (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS event_project_invite_attempts_user ON public.event_project_invite_attempts (user_id, at DESC);

CREATE TABLE IF NOT EXISTS public.event_project_change_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('lane_add', 'lane_rename', 'lane_archive', 'channel_add', 'channel_edit', 'channel_remove')),
  lane_id uuid REFERENCES public.event_project_lanes(id) ON DELETE CASCADE,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  why text NOT NULL CHECK (length(btrim(why)) BETWEEN 3 AND 140),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'declined')),
  proposed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  proposed_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  decided_at timestamptz,
  decision_reason text,
  CHECK (status <> 'declined' OR length(btrim(coalesce(decision_reason, ''))) BETWEEN 3 AND 140)
);

CREATE TABLE IF NOT EXISTS public.event_project_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  lane_id uuid NOT NULL REFERENCES public.event_project_lanes(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 60),
  assignee_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  due_date date,
  status text NOT NULL DEFAULT 'todo' CHECK (status IN ('todo', 'doing', 'blocked', 'done')),
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  deleted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  delete_reason text,
  CHECK (deleted_at IS NULL OR length(btrim(coalesce(delete_reason, ''))) BETWEEN 3 AND 140)
);
CREATE INDEX IF NOT EXISTS event_project_tasks_event ON public.event_project_tasks (event_id) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.event_project_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  lane_id uuid NOT NULL REFERENCES public.event_project_lanes(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('proposal', 'question', 'update', 'decision')),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 80),
  body text NOT NULL DEFAULT '' CHECK (length(body) <= 280),
  author_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  addressee_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  options jsonb,
  deadline date,
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'resolved', 'locked')),
  source_post_id uuid REFERENCES public.event_project_posts(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  edited_at timestamptz,
  resolved_at timestamptz,
  resolved_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  delete_reason text,
  CHECK ((type = 'proposal') = (options IS NOT NULL)),
  CHECK (options IS NULL OR (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) BETWEEN 2 AND 4)),
  CHECK (type <> 'decision' OR state = 'locked'),
  CHECK (deleted_at IS NULL OR length(btrim(coalesce(delete_reason, ''))) BETWEEN 3 AND 140)
);
CREATE INDEX IF NOT EXISTS event_project_posts_event ON public.event_project_posts (event_id, created_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.event_project_post_votes (
  post_id uuid NOT NULL REFERENCES public.event_project_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  option_index smallint NOT NULL CHECK (option_index BETWEEN 0 AND 3),
  voted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.event_project_post_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.event_project_posts(id) ON DELETE CASCADE,
  author_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 140),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS event_project_post_replies_post ON public.event_project_post_replies (post_id, created_at);

CREATE TABLE IF NOT EXISTS public.event_project_post_seen (
  post_id uuid NOT NULL REFERENCES public.event_project_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.event_project_ros_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 40),
  owner_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  done_at timestamptz,
  done_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  deleted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  delete_reason text,
  CHECK (ends_at >= starts_at + interval '10 minutes'),
  CHECK (deleted_at IS NULL OR length(btrim(coalesce(delete_reason, ''))) BETWEEN 3 AND 140)
);
CREATE INDEX IF NOT EXISTS event_project_ros_items_event ON public.event_project_ros_items (event_id, starts_at) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.event_project_log (
  id bigserial PRIMARY KEY,
  event_id text NOT NULL REFERENCES public.event_projects(event_id) ON DELETE CASCADE,
  actor_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_type text,
  target_id text,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS event_project_log_event ON public.event_project_log (event_id, at DESC);
CREATE INDEX IF NOT EXISTS event_project_log_target ON public.event_project_log (target_id) WHERE target_id IS NOT NULL;

-- ================================================================== who is who
-- THE Host definition. v1 = both organizer accounts, like is_event_host(). For owner_id only, change this one line to
-- `SELECT ARRAY[o.owner_id]` filtered the same way.
CREATE OR REPLACE FUNCTION public.project_host_ids(p_event_id text)
RETURNS uuid[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT coalesce((SELECT array_remove(ARRAY[o.owner_id, o.user_id], NULL)
                     FROM events e JOIN organizers o ON o.id = e.organizer_id WHERE e.id = p_event_id), ARRAY[]::uuid[]);
$$;

CREATE OR REPLACE FUNCTION public.project_is_host(p_event_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND auth.uid() = ANY (public.project_host_ids(p_event_id));
$$;

-- Host or active member of an existing project, with the hub switch on. Used by every RLS policy.
CREATE OR REPLACE FUNCTION public.is_event_project_member(p_event_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT public.app_flag('event_project_hub', false)
     AND EXISTS (SELECT 1 FROM event_projects p WHERE p.event_id = p_event_id)
     AND (public.project_is_host(p_event_id)
          OR EXISTS (SELECT 1 FROM event_project_members m
                      WHERE m.event_id = p_event_id AND m.user_id = auth.uid() AND m.status = 'active'));
$$;

-- A user who may own a task, be asked a question or own a run-of-show item: a Host or an active member.
CREATE OR REPLACE FUNCTION public.project_is_participant(p_event_id text, p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT p_user IS NOT NULL AND (p_user = ANY (public.project_host_ids(p_event_id))
     OR EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = p_event_id AND m.user_id = p_user AND m.status = 'active'));
$$;

-- The event's end: midnight after event_date in the event's zone, or the last run-of-show end if later.
CREATE OR REPLACE FUNCTION public.project_event_end(p_event_id text)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT GREATEST(
    (SELECT (coalesce(e.event_date, (e.starts_at AT TIME ZONE e.tz)::date) + 1)::timestamp AT TIME ZONE e.tz
       FROM events e WHERE e.id = p_event_id),
    (SELECT max(r.ends_at) FROM event_project_ros_items r WHERE r.event_id = p_event_id AND r.deleted_at IS NULL));
$$;

CREATE OR REPLACE FUNCTION public.project_read_only_at(p_event_id text)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT public.project_event_end(p_event_id) + make_interval(days => public.project_limit('readOnlyDays'));
$$;

-- Common checks for every RPC. Returns an error code or NULL. p_write adds the account gate and the read-only rule.
CREATE OR REPLACE FUNCTION public.project_guard(p_event_id text, p_write boolean)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_ro timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN RETURN 'AUTH_REQUIRED'; END IF;
  IF p_write AND NOT public.account_gate_ok() THEN RETURN 'ACCOUNT_GATE'; END IF;
  IF NOT public.app_flag('event_project_hub', false) THEN RETURN 'FEATURE_OFF'; END IF;
  IF NOT EXISTS (SELECT 1 FROM event_projects WHERE event_id = p_event_id) THEN RETURN 'NOT_FOUND'; END IF;
  IF NOT public.is_event_project_member(p_event_id) THEN RETURN 'NOT_AUTHORIZED'; END IF;
  IF p_write THEN
    v_ro := public.project_read_only_at(p_event_id);
    IF v_ro IS NOT NULL AND now() >= v_ro THEN RETURN 'READ_ONLY'; END IF;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.project_err(p_code text)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object('success', false, 'error', p_code) $$;

-- The caller's active membership row (all NULL for a Host without a row, or an outsider).
CREATE OR REPLACE FUNCTION public.project_me(p_event_id text)
RETURNS public.event_project_members LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT m.* FROM event_project_members m WHERE m.event_id = p_event_id AND m.user_id = auth.uid() AND m.status = 'active';
$$;

-- Bump the version (clients refresh with p_since_version) and append to the log, in the caller's transaction.
CREATE OR REPLACE FUNCTION public.project_touch(p_event_id text, p_action text, p_target_type text, p_target_id text, p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  UPDATE event_projects SET version = version + 1 WHERE event_id = p_event_id;
  INSERT INTO event_project_log (event_id, actor_id, action, target_type, target_id, detail)
  VALUES (p_event_id, auth.uid(), p_action, p_target_type, p_target_id, coalesce(p_detail, '{}'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.project_reason_ok(p_reason text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT length(btrim(coalesce(p_reason, ''))) BETWEEN public.project_limit('reasonMin') AND public.project_limit('reasonMax');
$$;

-- A post nobody else has responded to yet (no reply, no vote and no "seen" from anyone but its author).
CREATE OR REPLACE FUNCTION public.project_post_quiet(p_post_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT NOT EXISTS (SELECT 1 FROM event_project_post_replies r JOIN event_project_posts p ON p.id = r.post_id
                      WHERE r.post_id = p_post_id AND r.author_id IS DISTINCT FROM p.author_id)
     AND NOT EXISTS (SELECT 1 FROM event_project_post_votes v JOIN event_project_posts p ON p.id = v.post_id
                      WHERE v.post_id = p_post_id AND v.user_id IS DISTINCT FROM p.author_id)
     AND NOT EXISTS (SELECT 1 FROM event_project_post_seen s JOIN event_project_posts p ON p.id = s.post_id
                      WHERE s.post_id = p_post_id AND s.user_id IS DISTINCT FROM p.author_id);
$$;

-- Keep at most 30 items in a project's trash: anything older beyond that is deleted for good.
CREATE OR REPLACE FUNCTION public.project_trim_trash(p_event_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT kind, id FROM (
      SELECT 'task' AS kind, id, deleted_at AS at FROM event_project_tasks WHERE event_id = p_event_id AND deleted_at IS NOT NULL
      UNION ALL SELECT 'post', id, deleted_at FROM event_project_posts WHERE event_id = p_event_id AND deleted_at IS NOT NULL
      UNION ALL SELECT 'ros', id, deleted_at FROM event_project_ros_items WHERE event_id = p_event_id AND deleted_at IS NOT NULL
      UNION ALL SELECT 'lane', id, archived_at FROM event_project_lanes WHERE event_id = p_event_id AND archived_at IS NOT NULL
    ) t ORDER BY at DESC, id OFFSET public.project_limit('trashMax')
  LOOP
    IF r.kind = 'task' THEN DELETE FROM event_project_tasks WHERE id = r.id;
    ELSIF r.kind = 'post' THEN DELETE FROM event_project_posts WHERE id = r.id;
    ELSIF r.kind = 'ros' THEN DELETE FROM event_project_ros_items WHERE id = r.id;
    ELSE DELETE FROM event_project_lanes WHERE id = r.id;
    END IF;
  END LOOP;
END;
$$;

-- ================================================================== RLS (read only; writes are RPCs)
ALTER TABLE public.event_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_lanes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_invite_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_post_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_post_replies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_post_seen ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_ros_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_project_log ENABLE ROW LEVEL SECURITY;

-- Supabase grants new public tables to anon and authenticated by default: take that back, then allow SELECT only.
REVOKE ALL ON public.event_projects, public.event_project_lanes, public.event_project_members, public.event_project_invites,
  public.event_project_invite_attempts, public.event_project_change_requests, public.event_project_tasks,
  public.event_project_posts, public.event_project_post_votes, public.event_project_post_replies,
  public.event_project_post_seen, public.event_project_ros_items, public.event_project_log FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.event_project_invite_attempts_id_seq, public.event_project_log_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.event_projects, public.event_project_lanes, public.event_project_members, public.event_project_invites,
  public.event_project_change_requests, public.event_project_tasks, public.event_project_posts,
  public.event_project_post_votes, public.event_project_post_replies, public.event_project_post_seen,
  public.event_project_ros_items, public.event_project_log TO authenticated;

DROP POLICY IF EXISTS event_projects_select ON public.event_projects;
CREATE POLICY event_projects_select ON public.event_projects FOR SELECT TO authenticated USING (public.is_event_project_member(event_id));
DROP POLICY IF EXISTS event_project_lanes_select ON public.event_project_lanes;
CREATE POLICY event_project_lanes_select ON public.event_project_lanes FOR SELECT TO authenticated USING (public.is_event_project_member(event_id));
DROP POLICY IF EXISTS event_project_members_select ON public.event_project_members;
CREATE POLICY event_project_members_select ON public.event_project_members FOR SELECT TO authenticated USING (public.is_event_project_member(event_id));
-- Invites hold the joining token: only the Host and the invite's creator see them.
DROP POLICY IF EXISTS event_project_invites_select ON public.event_project_invites;
CREATE POLICY event_project_invites_select ON public.event_project_invites FOR SELECT TO authenticated USING (
  public.is_event_project_member(event_id) AND (public.project_is_host(event_id) OR created_by = auth.uid()));
-- Proposals: the Host and the proposer.
DROP POLICY IF EXISTS event_project_change_requests_select ON public.event_project_change_requests;
CREATE POLICY event_project_change_requests_select ON public.event_project_change_requests FOR SELECT TO authenticated USING (
  public.is_event_project_member(event_id) AND (public.project_is_host(event_id) OR proposed_by = auth.uid()));
DROP POLICY IF EXISTS event_project_tasks_select ON public.event_project_tasks;
CREATE POLICY event_project_tasks_select ON public.event_project_tasks FOR SELECT TO authenticated USING (public.is_event_project_member(event_id));
DROP POLICY IF EXISTS event_project_posts_select ON public.event_project_posts;
CREATE POLICY event_project_posts_select ON public.event_project_posts FOR SELECT TO authenticated USING (public.is_event_project_member(event_id));
DROP POLICY IF EXISTS event_project_post_votes_select ON public.event_project_post_votes;
CREATE POLICY event_project_post_votes_select ON public.event_project_post_votes FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.event_project_posts p WHERE p.id = post_id AND public.is_event_project_member(p.event_id)));
DROP POLICY IF EXISTS event_project_post_replies_select ON public.event_project_post_replies;
CREATE POLICY event_project_post_replies_select ON public.event_project_post_replies FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.event_project_posts p WHERE p.id = post_id AND public.is_event_project_member(p.event_id)));
DROP POLICY IF EXISTS event_project_post_seen_select ON public.event_project_post_seen;
CREATE POLICY event_project_post_seen_select ON public.event_project_post_seen FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.event_project_posts p WHERE p.id = post_id AND public.is_event_project_member(p.event_id)));
DROP POLICY IF EXISTS event_project_ros_items_select ON public.event_project_ros_items;
CREATE POLICY event_project_ros_items_select ON public.event_project_ros_items FOR SELECT TO authenticated USING (public.is_event_project_member(event_id));
DROP POLICY IF EXISTS event_project_log_select ON public.event_project_log;
CREATE POLICY event_project_log_select ON public.event_project_log FOR SELECT TO authenticated USING (public.is_event_project_member(event_id));
-- event_project_invite_attempts: no policy and no grant at all.

-- ================================================================== reads
CREATE OR REPLACE FUNCTION public.project_people(p_ids uuid[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('user_id', p.id, 'display_name', p.display_name, 'handle', p.handle,
                                               'avatar_url', p.avatar_url) ORDER BY p.display_name), '[]'::jsonb)
    FROM profiles p WHERE p.id = ANY (p_ids);
$$;

CREATE OR REPLACE FUNCTION public.project_post_json(p_post public.event_project_posts)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT to_jsonb(p_post) - 'deleted_at' - 'deleted_by' - 'delete_reason' || jsonb_build_object(
    'votes', CASE WHEN p_post.type = 'proposal' THEN (
      SELECT jsonb_agg(coalesce((SELECT count(*) FROM event_project_post_votes v WHERE v.post_id = p_post.id AND v.option_index = i), 0) ORDER BY i)
        FROM generate_series(0, jsonb_array_length(p_post.options) - 1) i) END,
    'my_vote', (SELECT v.option_index FROM event_project_post_votes v WHERE v.post_id = p_post.id AND v.user_id = auth.uid()),
    'replies_count', (SELECT count(*) FROM event_project_post_replies r WHERE r.post_id = p_post.id),
    'seen_count', (SELECT count(*) FROM event_project_post_seen s WHERE s.post_id = p_post.id),
    'seen_by_me', EXISTS (SELECT 1 FROM event_project_post_seen s WHERE s.post_id = p_post.id AND s.user_id = auth.uid()),
    'quiet', public.project_post_quiet(p_post.id));
$$;

-- One snapshot for the hub screen. With p_since_version equal to the current version it answers {unchanged: true}
-- (the client keeps its copy: one tiny request instead of the whole project).
CREATE OR REPLACE FUNCTION public.get_event_project(p_event_id text, p_since_version bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_err text := public.project_guard(p_event_id, false);
  v_p event_projects%ROWTYPE;
  v_me event_project_members%ROWTYPE;
  v_host boolean;
  v_end timestamptz;
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  SELECT * INTO v_p FROM event_projects WHERE event_id = p_event_id;
  IF p_since_version IS NOT NULL AND p_since_version = v_p.version THEN
    RETURN jsonb_build_object('success', true, 'unchanged', true, 'version', v_p.version);
  END IF;
  v_host := public.project_is_host(p_event_id);
  v_me := public.project_me(p_event_id);
  v_end := public.project_event_end(p_event_id);
  RETURN jsonb_build_object(
    'success', true, 'unchanged', false, 'version', v_p.version,
    'project', jsonb_build_object(
      'event_id', v_p.event_id, 'started_at', v_p.started_at, 'channels', v_p.channels, 'refund_approval', v_p.refund_approval,
      'event_end_at', v_end, 'read_only_at', public.project_read_only_at(p_event_id),
      'read_only', now() >= public.project_read_only_at(p_event_id)),
    'event', (SELECT jsonb_build_object('id', e.id, 'name', e.name, 'event_date', e.event_date, 'event_time', e.event_time,
                                        'starts_at', e.starts_at, 'tz', e.tz, 'status', e.status)
                FROM events e WHERE e.id = p_event_id),
    'is_host', v_host,
    'me', CASE WHEN v_me.id IS NULL THEN NULL ELSE jsonb_build_object(
      'member_id', v_me.id, 'role', v_me.role, 'lane_id', v_me.lane_id,
      'cap_money', v_me.role = 'finance' OR v_me.cap_money, 'cap_checkin', v_me.role = 'finance' OR v_me.cap_checkin,
      'grant_expires_at', coalesce(v_me.grant_expires_at, v_end + make_interval(days => public.project_limit('grantDays')))) END,
    'hosts', public.project_people(public.project_host_ids(p_event_id)),
    'members', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'member_id', m.id, 'user_id', m.user_id, 'role', m.role, 'lane_id', m.lane_id,
        'cap_money', m.role = 'finance' OR m.cap_money, 'cap_checkin', m.role = 'finance' OR m.cap_checkin,
        'joined_at', m.joined_at, 'display_name', pr.display_name, 'handle', pr.handle, 'avatar_url', pr.avatar_url)
        ORDER BY m.joined_at)
      FROM event_project_members m JOIN profiles pr ON pr.id = m.user_id
      WHERE m.event_id = p_event_id AND m.status = 'active'), '[]'::jsonb),
    'lanes', coalesce((SELECT jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'position', l.position) ORDER BY l.position, l.created_at)
      FROM event_project_lanes l WHERE l.event_id = p_event_id AND l.archived_at IS NULL), '[]'::jsonb),
    'tasks', coalesce((SELECT jsonb_agg(to_jsonb(t) - 'deleted_at' - 'deleted_by' - 'delete_reason' ORDER BY t.due_date NULLS LAST, t.created_at)
      FROM (SELECT * FROM event_project_tasks t WHERE t.event_id = p_event_id AND t.deleted_at IS NULL
              AND (t.status <> 'done' OR t.updated_at > now() - interval '14 days')
            ORDER BY t.due_date NULLS LAST, t.created_at LIMIT 300) t), '[]'::jsonb),
    'posts', coalesce((SELECT jsonb_agg(public.project_post_json(p) ORDER BY p.created_at DESC)
      FROM (SELECT * FROM event_project_posts p WHERE p.event_id = p_event_id AND p.deleted_at IS NULL
            ORDER BY p.created_at DESC LIMIT 20) p), '[]'::jsonb),
    'ros', coalesce((SELECT jsonb_agg(to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason' ORDER BY r.starts_at, r.id)
      FROM event_project_ros_items r WHERE r.event_id = p_event_id AND r.deleted_at IS NULL), '[]'::jsonb),
    'change_requests', coalesce((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.proposed_at DESC)
      FROM event_project_change_requests c WHERE c.event_id = p_event_id
        AND (c.status = 'pending' OR c.decided_at > now() - interval '30 days')
        AND (v_host OR c.proposed_by = auth.uid())), '[]'::jsonb));
END;
$$;

-- Older posts, 20 at a time.
CREATE OR REPLACE FUNCTION public.get_event_project_posts(p_event_id text, p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, false);
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  RETURN jsonb_build_object('success', true, 'posts', coalesce((SELECT jsonb_agg(public.project_post_json(p) ORDER BY p.created_at DESC)
    FROM (SELECT * FROM event_project_posts p WHERE p.event_id = p_event_id AND p.deleted_at IS NULL
            AND (p_before IS NULL OR p.created_at < p_before)
          ORDER BY p.created_at DESC LIMIT LEAST(GREATEST(coalesce(p_limit, 20), 1), 50)) p), '[]'::jsonb));
END;
$$;

-- One post with its replies, voters and who has seen it.
CREATE OR REPLACE FUNCTION public.get_event_project_post(p_post_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text;
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, false);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  RETURN jsonb_build_object('success', true, 'post', public.project_post_json(v_p),
    'replies', coalesce((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'author_id', r.author_id, 'body', r.body, 'created_at', r.created_at) ORDER BY r.created_at)
      FROM event_project_post_replies r WHERE r.post_id = p_post_id), '[]'::jsonb),
    'voters', coalesce((SELECT jsonb_agg(jsonb_build_object('user_id', v.user_id, 'option_index', v.option_index))
      FROM event_project_post_votes v WHERE v.post_id = p_post_id), '[]'::jsonb),
    'seen_by', coalesce((SELECT jsonb_agg(s.user_id ORDER BY s.seen_at) FROM event_project_post_seen s WHERE s.post_id = p_post_id), '[]'::jsonb));
END;
$$;

-- Trash (Host and Manager): items deleted in the last 7 days and archived lanes.
CREATE OR REPLACE FUNCTION public.get_event_project_trash(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, false);
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT coalesce((public.project_is_host(p_event_id) OR (public.project_me(p_event_id)).role = 'manager'), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  RETURN jsonb_build_object('success', true, 'items', coalesce((SELECT jsonb_agg(x ORDER BY x->>'at' DESC) FROM (
      SELECT jsonb_build_object('kind', 'task', 'id', id, 'title', title, 'by', deleted_by, 'reason', delete_reason, 'at', deleted_at) x
        FROM event_project_tasks WHERE event_id = p_event_id AND deleted_at > now() - make_interval(days => public.project_limit('trashDays'))
      UNION ALL SELECT jsonb_build_object('kind', 'post', 'id', id, 'title', title, 'by', deleted_by, 'reason', delete_reason, 'at', deleted_at)
        FROM event_project_posts WHERE event_id = p_event_id AND deleted_at > now() - make_interval(days => public.project_limit('trashDays'))
      UNION ALL SELECT jsonb_build_object('kind', 'ros', 'id', id, 'title', title, 'starts_at', starts_at, 'by', deleted_by, 'reason', delete_reason, 'at', deleted_at)
        FROM event_project_ros_items WHERE event_id = p_event_id AND deleted_at > now() - make_interval(days => public.project_limit('trashDays'))
      UNION ALL SELECT jsonb_build_object('kind', 'lane', 'id', id, 'title', name, 'by', archived_by, 'reason', archive_reason, 'at', archived_at)
        FROM event_project_lanes WHERE event_id = p_event_id AND archived_at IS NOT NULL) t), '[]'::jsonb));
END;
$$;

-- Event-day poll: run-of-show only, {unchanged} when nothing moved.
CREATE OR REPLACE FUNCTION public.get_event_project_ros(p_event_id text, p_since_version bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, false); v_version bigint;
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  SELECT version INTO v_version FROM event_projects WHERE event_id = p_event_id;
  IF p_since_version IS NOT NULL AND p_since_version = v_version THEN
    RETURN jsonb_build_object('success', true, 'unchanged', true, 'version', v_version);
  END IF;
  RETURN jsonb_build_object('success', true, 'unchanged', false, 'version', v_version,
    'ros', coalesce((SELECT jsonb_agg(to_jsonb(r) - 'deleted_at' - 'deleted_by' - 'delete_reason' ORDER BY r.starts_at, r.id)
      FROM event_project_ros_items r WHERE r.event_id = p_event_id AND r.deleted_at IS NULL), '[]'::jsonb));
END;
$$;

-- Account > "Projects I'm in": projects where the caller is a Host or an active member.
CREATE OR REPLACE FUNCTION public.get_my_event_projects()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN public.project_err('AUTH_REQUIRED'); END IF;
  IF NOT public.app_flag('event_project_hub', false) THEN RETURN jsonb_build_object('success', true, 'projects', '[]'::jsonb); END IF;
  RETURN jsonb_build_object('success', true, 'projects', coalesce((SELECT jsonb_agg(x ORDER BY x->>'starts_at') FROM (
    SELECT jsonb_build_object(
      'event_id', e.id, 'name', e.name, 'event_date', e.event_date, 'starts_at', e.starts_at, 'tz', e.tz, 'status', e.status,
      'role', CASE WHEN auth.uid() = ANY (public.project_host_ids(e.id)) THEN 'host' ELSE m.role END,
      'my_open_tasks', (SELECT count(*) FROM event_project_tasks t WHERE t.event_id = e.id AND t.deleted_at IS NULL
                          AND t.status <> 'done' AND t.assignee_id = auth.uid()),
      'read_only', now() >= public.project_read_only_at(e.id)) x
    FROM event_projects p JOIN events e ON e.id = p.event_id
    LEFT JOIN event_project_members m ON m.event_id = p.event_id AND m.user_id = auth.uid() AND m.status = 'active'
    WHERE auth.uid() = ANY (public.project_host_ids(e.id)) OR m.id IS NOT NULL) t), '[]'::jsonb));
END;
$$;

-- ================================================================== start a project (Host, opt-in)
CREATE OR REPLACE FUNCTION public.start_event_project(p_event_id text, p_lane_names text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_name text;
  v_i int := 0;
  v_names text[] := ARRAY[]::text[];
BEGIN
  IF auth.uid() IS NULL THEN RETURN public.project_err('AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN public.project_err('ACCOUNT_GATE'); END IF;
  IF NOT public.app_flag('event_project_hub', false) THEN RETURN public.project_err('FEATURE_OFF'); END IF;
  SELECT * INTO v_ev FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN RETURN public.project_err('NOT_FOUND'); END IF;
  IF NOT public.project_is_host(p_event_id) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF v_ev.status::text IN ('cancelled', 'removed') THEN RETURN public.project_err('EVENT_CLOSED'); END IF;
  IF v_ev.event_date IS NULL AND v_ev.starts_at IS NULL THEN RETURN public.project_err('EVENT_NOT_SCHEDULED'); END IF;
  IF EXISTS (SELECT 1 FROM event_projects WHERE event_id = p_event_id) THEN RETURN public.project_err('ALREADY_STARTED'); END IF;
  IF now() >= ((coalesce(v_ev.event_date, (v_ev.starts_at AT TIME ZONE v_ev.tz)::date) + 1)::timestamp AT TIME ZONE v_ev.tz)
             + make_interval(days => public.project_limit('readOnlyDays')) THEN
    RETURN public.project_err('READ_ONLY');
  END IF;
  -- Starting lanes come from the client in the Host's language; duplicates and blanks are dropped.
  FOREACH v_name IN ARRAY coalesce(p_lane_names, ARRAY[]::text[]) LOOP
    v_name := btrim(v_name);
    CONTINUE WHEN v_name = '' OR lower(v_name) = ANY (SELECT lower(x) FROM unnest(v_names) x);
    IF length(v_name) > public.project_limit('laneNameMax') THEN RETURN public.project_err('LANE_NAME_INVALID'); END IF;
    v_names := v_names || v_name;
  END LOOP;
  IF cardinality(v_names) > public.project_limit('lanesMax') THEN RETURN public.project_err('LANES_FULL'); END IF;

  INSERT INTO event_projects (event_id, started_by) VALUES (p_event_id, auth.uid());
  FOREACH v_name IN ARRAY v_names LOOP
    INSERT INTO event_project_lanes (event_id, name, position, created_by) VALUES (p_event_id, v_name, v_i, auth.uid());
    v_i := v_i + 1;
  END LOOP;
  INSERT INTO event_project_log (event_id, actor_id, action, detail)
  VALUES (p_event_id, auth.uid(), 'project.start', jsonb_build_object('lanes', cardinality(v_names)));
  RETURN jsonb_build_object('success', true, 'event_id', p_event_id, 'version', 1);
END;
$$;

-- ================================================================== invites
CREATE OR REPLACE FUNCTION public.project_new_token()
RETURNS text LANGUAGE sql VOLATILE AS $$
  SELECT rtrim(translate(encode(decode(replace(gen_random_uuid()::text, '-', ''), 'hex'), 'base64'), '+/', '-_'), '=');
$$;

CREATE OR REPLACE FUNCTION public.project_new_code()
RETURNS text LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  v_alpha constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes bytea; v_code text;
BEGIN
  FOR attempt IN 1..40 LOOP
    v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
    v_code := 'BB-' || substr(v_alpha, 1 + get_byte(v_bytes, 1) % 31, 1) || substr(v_alpha, 1 + get_byte(v_bytes, 3) % 31, 1)
                    || substr(v_alpha, 1 + get_byte(v_bytes, 5) % 31, 1) || substr(v_alpha, 1 + get_byte(v_bytes, 9) % 31, 1);
    IF NOT EXISTS (SELECT 1 FROM public.event_project_invites WHERE short_code = v_code AND revoked_at IS NULL) THEN RETURN v_code; END IF;
  END LOOP;
  RAISE EXCEPTION 'no free invite code';
END;
$$;

-- A typed code or a token -> the normalized value (same rules as src/lib/projectInviteLink.js), or NULL.
CREATE OR REPLACE FUNCTION public.project_invite_value(p_input text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text := btrim(coalesce(p_input, ''));
BEGIN
  IF v ~ '^[A-Za-z0-9_-]{22}$' THEN RETURN v; END IF;
  v := regexp_replace(upper(v), '[[:space:]\-‐‑‒–—―]', '', 'g');
  IF left(v, 2) = 'BB' AND length(v) = 6 THEN v := substr(v, 3); END IF;
  IF v ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}$' THEN RETURN 'BB-' || v; END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.project_invite_find(p_input text)
RETURNS public.event_project_invites LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT i.* FROM event_project_invites i
   WHERE (i.token = public.project_invite_value(p_input))
      OR (i.short_code = public.project_invite_value(p_input) AND i.revoked_at IS NULL)
   ORDER BY i.created_at DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.project_invite_rate_limited()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT count(*) >= 10 FROM event_project_invite_attempts WHERE user_id = auth.uid() AND at > now() - interval '1 hour';
$$;

CREATE OR REPLACE FUNCTION public.project_create_invite(p_event_id text, p_role text, p_lane_id uuid DEFAULT NULL, p_max_uses int DEFAULT 1)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_err text := public.project_guard(p_event_id, true);
  v_host boolean; v_me event_project_members%ROWTYPE;
  v_inv event_project_invites%ROWTYPE;
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_host := public.project_is_host(p_event_id);
  v_me := public.project_me(p_event_id);
  IF NOT coalesce(((v_host AND p_role IN ('manager', 'finance', 'lane_lead', 'helper'))
          OR (v_me.role = 'manager' AND p_role IN ('lane_lead', 'helper'))), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  IF p_role = 'lane_lead' AND NOT EXISTS (SELECT 1 FROM event_project_lanes WHERE id = p_lane_id AND event_id = p_event_id AND archived_at IS NULL) THEN
    RETURN public.project_err('LANE_REQUIRED');
  END IF;
  IF coalesce(p_max_uses, 1) NOT BETWEEN 1 AND public.project_limit('inviteMaxUses') THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  IF coalesce(p_max_uses, 1) > 1 AND NOT public.app_flag('project_qr_invite', false) THEN RETURN public.project_err('FEATURE_OFF'); END IF;
  INSERT INTO event_project_invites (event_id, token, short_code, role, lane_id, created_by, expires_at, max_uses)
  VALUES (p_event_id, public.project_new_token(), public.project_new_code(), p_role,
          CASE WHEN p_role = 'lane_lead' THEN p_lane_id END, auth.uid(),
          now() + make_interval(hours => public.project_limit('inviteHours')), coalesce(p_max_uses, 1))
  RETURNING * INTO v_inv;
  PERFORM public.project_touch(p_event_id, 'invite.create', 'invite', v_inv.id::text, jsonb_build_object('role', p_role, 'max_uses', v_inv.max_uses));
  RETURN jsonb_build_object('success', true, 'invite_id', v_inv.id, 'token', v_inv.token, 'short_code', v_inv.short_code,
                            'role', v_inv.role, 'lane_id', v_inv.lane_id, 'expires_at', v_inv.expires_at, 'max_uses', v_inv.max_uses);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_list_invites(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, false); v_host boolean := public.project_is_host(p_event_id);
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT v_host AND (public.project_me(p_event_id)).role IS DISTINCT FROM 'manager' THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  RETURN jsonb_build_object('success', true, 'invites', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'invite_id', i.id, 'token', i.token, 'short_code', i.short_code, 'role', i.role, 'lane_id', i.lane_id, 'created_by', i.created_by,
      'expires_at', i.expires_at, 'max_uses', i.max_uses, 'uses', i.uses) ORDER BY i.created_at DESC)
    FROM event_project_invites i WHERE i.event_id = p_event_id AND i.revoked_at IS NULL AND i.expires_at > now() AND i.uses < i.max_uses
      AND (v_host OR i.created_by = auth.uid())), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.project_revoke_invite(p_invite_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_inv event_project_invites%ROWTYPE; v_err text;
BEGIN
  SELECT * INTO v_inv FROM event_project_invites WHERE id = p_invite_id;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_inv.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT coalesce((public.project_is_host(v_inv.event_id) OR ((public.project_me(v_inv.event_id)).role = 'manager' AND v_inv.created_by = auth.uid())), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  UPDATE event_project_invites SET revoked_at = coalesce(revoked_at, now()) WHERE id = p_invite_id;
  PERFORM public.project_touch(v_inv.event_id, 'invite.revoke', 'invite', p_invite_id::text);
  RETURN jsonb_build_object('success', true);
END;
$$;

-- What a scanned link or typed code points at, for the "Join as Helper?" screen. Signed-in only; failures count
-- toward the 10-per-hour lock (a 4-character code must not be guessable).
CREATE OR REPLACE FUNCTION public.peek_project_invite(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_inv event_project_invites%ROWTYPE; v_ev events%ROWTYPE; v_state text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN public.project_err('AUTH_REQUIRED'); END IF;
  IF NOT public.app_flag('event_project_hub', false) THEN RETURN public.project_err('FEATURE_OFF'); END IF;
  IF public.project_invite_rate_limited() THEN RETURN public.project_err('RATE_LIMITED'); END IF;
  v_inv := public.project_invite_find(p_code);
  IF v_inv.id IS NULL THEN
    INSERT INTO event_project_invite_attempts (user_id) VALUES (auth.uid());
    RETURN public.project_err('INVITE_NOT_FOUND');
  END IF;
  SELECT * INTO v_ev FROM events WHERE id = v_inv.event_id;
  v_state := CASE
    WHEN v_inv.revoked_at IS NOT NULL THEN 'revoked'
    WHEN v_inv.expires_at <= now() THEN 'expired'
    WHEN v_inv.uses >= v_inv.max_uses THEN 'used'
    WHEN v_ev.status::text IN ('cancelled', 'removed') OR now() >= public.project_read_only_at(v_inv.event_id) THEN 'event_closed'
    WHEN auth.uid() = ANY (public.project_host_ids(v_inv.event_id)) THEN 'is_host'
    WHEN EXISTS (SELECT 1 FROM event_project_members m WHERE m.event_id = v_inv.event_id AND m.user_id = auth.uid() AND m.status = 'active') THEN 'already_member'
    ELSE 'ok' END;
  RETURN jsonb_build_object('success', true, 'state', v_state, 'event_id', v_ev.id, 'event_name', v_ev.name,
    'event_date', v_ev.event_date, 'starts_at', v_ev.starts_at, 'tz', v_ev.tz,
    'organizer_name', (SELECT o.name FROM organizers o WHERE o.id = v_ev.organizer_id),
    'role', v_inv.role, 'lane_name', (SELECT l.name FROM event_project_lanes l WHERE l.id = v_inv.lane_id),
    'expires_at', v_inv.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_redeem_invite(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_found event_project_invites%ROWTYPE;
  v_inv event_project_invites%ROWTYPE;
  v_ev events%ROWTYPE;
  v_member_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RETURN public.project_err('AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN public.project_err('ACCOUNT_GATE'); END IF;
  IF NOT public.app_flag('event_project_hub', false) THEN RETURN public.project_err('FEATURE_OFF'); END IF;
  IF public.project_invite_rate_limited() THEN RETURN public.project_err('RATE_LIMITED'); END IF;
  v_found := public.project_invite_find(p_code);
  IF v_found.id IS NULL THEN
    INSERT INTO event_project_invite_attempts (user_id) VALUES (auth.uid());
    RETURN public.project_err('INVITE_NOT_FOUND');
  END IF;
  SELECT * INTO v_inv FROM event_project_invites WHERE id = v_found.id FOR UPDATE;
  SELECT * INTO v_ev FROM events WHERE id = v_inv.event_id;
  IF v_inv.revoked_at IS NOT NULL THEN RETURN public.project_err('INVITE_REVOKED'); END IF;
  IF v_inv.expires_at <= now() THEN RETURN public.project_err('INVITE_EXPIRED'); END IF;
  IF v_inv.uses >= v_inv.max_uses THEN RETURN public.project_err('INVITE_USED'); END IF;
  IF v_ev.status::text IN ('cancelled', 'removed') OR now() >= public.project_read_only_at(v_inv.event_id) THEN
    RETURN public.project_err('EVENT_CLOSED');
  END IF;
  IF auth.uid() = ANY (public.project_host_ids(v_inv.event_id)) THEN RETURN public.project_err('IS_HOST'); END IF;
  IF EXISTS (SELECT 1 FROM event_project_members WHERE event_id = v_inv.event_id AND user_id = auth.uid() AND status = 'active') THEN
    RETURN public.project_err('ALREADY_MEMBER');
  END IF;
  IF v_inv.role = 'lane_lead' AND NOT EXISTS (SELECT 1 FROM event_project_lanes WHERE id = v_inv.lane_id AND archived_at IS NULL) THEN
    RETURN public.project_err('LANE_ARCHIVED');
  END IF;
  -- A removed member who is invited again comes back with the new role; nothing from the old row is kept.
  INSERT INTO event_project_members (event_id, user_id, role, lane_id, cap_money, cap_checkin, status, invited_by, joined_at)
  VALUES (v_inv.event_id, auth.uid(), v_inv.role, v_inv.lane_id, v_inv.role = 'finance', v_inv.role = 'finance', 'active', v_inv.created_by, now())
  ON CONFLICT (event_id, user_id) DO UPDATE SET role = excluded.role, lane_id = excluded.lane_id, cap_money = excluded.cap_money,
    cap_checkin = excluded.cap_checkin, status = 'active', invited_by = excluded.invited_by, joined_at = now(),
    removed_at = NULL, removed_by = NULL, grant_expires_at = NULL
  RETURNING id INTO v_member_id;
  UPDATE event_project_invites SET uses = uses + 1 WHERE id = v_inv.id;
  PERFORM public.project_touch(v_inv.event_id, 'member.join', 'member', v_member_id::text,
                               jsonb_build_object('role', v_inv.role, 'invite_id', v_inv.id));
  IF v_inv.created_by IS NOT NULL THEN
    INSERT INTO notifications (recipient_id, kind, title, body, data)
    VALUES (v_inv.created_by, 'project_joined', 'Thành viên mới',
            coalesce((SELECT nullif(display_name, '') FROM profiles WHERE id = auth.uid()), 'Một người') || ' đã vào dự án ' || v_ev.name || '.',
            jsonb_build_object('screen', 'event_project', 'event_id', v_inv.event_id));
  END IF;
  RETURN jsonb_build_object('success', true, 'event_id', v_inv.event_id, 'member_id', v_member_id, 'role', v_inv.role);
END;
$$;

-- ================================================================== members (Host)
CREATE OR REPLACE FUNCTION public.project_set_member(p_member_id uuid, p_role text DEFAULT NULL, p_lane_id uuid DEFAULT NULL,
                                                      p_cap_money boolean DEFAULT NULL, p_cap_checkin boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m event_project_members%ROWTYPE; v_err text; v_role text; v_lane uuid;
BEGIN
  SELECT * INTO v_m FROM event_project_members WHERE id = p_member_id AND status = 'active';
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_m.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT public.project_is_host(v_m.event_id) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  v_role := coalesce(p_role, v_m.role);
  IF v_role NOT IN ('manager', 'finance', 'lane_lead', 'helper') THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  v_lane := CASE WHEN v_role = 'lane_lead' THEN coalesce(p_lane_id, v_m.lane_id) END;
  IF v_role = 'lane_lead' AND NOT EXISTS (SELECT 1 FROM event_project_lanes WHERE id = v_lane AND event_id = v_m.event_id AND archived_at IS NULL) THEN
    RETURN public.project_err('LANE_REQUIRED');
  END IF;
  UPDATE event_project_members SET role = v_role, lane_id = v_lane,
    cap_money = CASE WHEN v_role = 'finance' THEN true ELSE coalesce(p_cap_money, CASE WHEN v_m.role = 'finance' THEN false ELSE cap_money END) END,
    cap_checkin = CASE WHEN v_role = 'finance' THEN true ELSE coalesce(p_cap_checkin, CASE WHEN v_m.role = 'finance' THEN false ELSE cap_checkin END) END
  WHERE id = p_member_id RETURNING * INTO v_m;
  PERFORM public.project_touch(v_m.event_id, 'member.set', 'member', p_member_id::text,
    jsonb_build_object('role', v_m.role, 'lane_id', v_m.lane_id, 'cap_money', v_m.cap_money, 'cap_checkin', v_m.cap_checkin));
  RETURN jsonb_build_object('success', true, 'member_id', v_m.id, 'role', v_m.role, 'lane_id', v_m.lane_id,
                            'cap_money', v_m.cap_money, 'cap_checkin', v_m.cap_checkin);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_remove_member(p_member_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_m event_project_members%ROWTYPE; v_err text;
BEGIN
  SELECT * INTO v_m FROM event_project_members WHERE id = p_member_id AND status = 'active';
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_m.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT public.project_is_host(v_m.event_id) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  UPDATE event_project_members SET status = 'removed', removed_at = now(), removed_by = auth.uid(), cap_money = false, cap_checkin = false
   WHERE id = p_member_id;
  -- Their open tasks go back to "unassigned" so nothing silently stalls.
  UPDATE event_project_tasks SET assignee_id = NULL, updated_at = now()
   WHERE event_id = v_m.event_id AND assignee_id = v_m.user_id AND status <> 'done' AND deleted_at IS NULL;
  PERFORM public.project_touch(v_m.event_id, 'member.remove', 'member', p_member_id::text, jsonb_build_object('reason', left(btrim(coalesce(p_reason, '')), 140)));
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_leave(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_me event_project_members%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN public.project_err('AUTH_REQUIRED'); END IF;
  v_me := public.project_me(p_event_id);
  IF v_me.id IS NULL THEN RETURN public.project_err('NOT_A_MEMBER'); END IF;
  UPDATE event_project_members SET status = 'removed', removed_at = now(), removed_by = auth.uid(), cap_money = false, cap_checkin = false
   WHERE id = v_me.id;
  UPDATE event_project_tasks SET assignee_id = NULL, updated_at = now()
   WHERE event_id = p_event_id AND assignee_id = auth.uid() AND status <> 'done' AND deleted_at IS NULL;
  PERFORM public.project_touch(p_event_id, 'member.leave', 'member', v_me.id::text);
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ================================================================== lanes and channels (Host applies; Manager proposes)
-- Internal appliers, shared by the Host's own RPCs and by approving a Manager's proposal. Not callable by clients.
CREATE OR REPLACE FUNCTION public.project_apply_lane_add(p_event_id text, p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_name text := btrim(coalesce(p_name, '')); v_id uuid;
BEGIN
  IF length(v_name) NOT BETWEEN 1 AND public.project_limit('laneNameMax') THEN RETURN public.project_err('LANE_NAME_INVALID'); END IF;
  IF (SELECT count(*) FROM event_project_lanes WHERE event_id = p_event_id AND archived_at IS NULL) >= public.project_limit('lanesMax') THEN
    RETURN public.project_err('LANES_FULL');
  END IF;
  IF EXISTS (SELECT 1 FROM event_project_lanes WHERE event_id = p_event_id AND archived_at IS NULL AND lower(btrim(name)) = lower(v_name)) THEN
    RETURN public.project_err('LANE_NAME_TAKEN');
  END IF;
  INSERT INTO event_project_lanes (event_id, name, position, created_by)
  VALUES (p_event_id, v_name, coalesce((SELECT max(position) + 1 FROM event_project_lanes WHERE event_id = p_event_id), 0), auth.uid())
  RETURNING id INTO v_id;
  PERFORM public.project_touch(p_event_id, 'lane.add', 'lane', v_id::text, jsonb_build_object('name', v_name));
  RETURN jsonb_build_object('success', true, 'lane_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_apply_lane_rename(p_lane_id uuid, p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_l event_project_lanes%ROWTYPE; v_name text := btrim(coalesce(p_name, ''));
BEGIN
  SELECT * INTO v_l FROM event_project_lanes WHERE id = p_lane_id AND archived_at IS NULL;
  IF NOT FOUND THEN RETURN public.project_err('NOT_FOUND'); END IF;
  IF length(v_name) NOT BETWEEN 1 AND public.project_limit('laneNameMax') THEN RETURN public.project_err('LANE_NAME_INVALID'); END IF;
  IF EXISTS (SELECT 1 FROM event_project_lanes WHERE event_id = v_l.event_id AND archived_at IS NULL AND id <> p_lane_id
               AND lower(btrim(name)) = lower(v_name)) THEN
    RETURN public.project_err('LANE_NAME_TAKEN');
  END IF;
  UPDATE event_project_lanes SET name = v_name WHERE id = p_lane_id;
  PERFORM public.project_touch(v_l.event_id, 'lane.rename', 'lane', p_lane_id::text, jsonb_build_object('from', v_l.name, 'to', v_name));
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_apply_lane_archive(p_lane_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_l event_project_lanes%ROWTYPE;
BEGIN
  SELECT * INTO v_l FROM event_project_lanes WHERE id = p_lane_id AND archived_at IS NULL;
  IF NOT FOUND THEN RETURN public.project_err('NOT_FOUND'); END IF;
  IF NOT public.project_reason_ok(p_reason) THEN RETURN public.project_err('REASON_REQUIRED'); END IF;
  IF EXISTS (SELECT 1 FROM event_project_tasks WHERE lane_id = p_lane_id AND deleted_at IS NULL AND status <> 'done') THEN
    RETURN public.project_err('LANE_HAS_OPEN_TASKS');
  END IF;
  UPDATE event_project_lanes SET archived_at = now(), archived_by = auth.uid(), archive_reason = btrim(p_reason) WHERE id = p_lane_id;
  PERFORM public.project_trim_trash(v_l.event_id);
  PERFORM public.project_touch(v_l.event_id, 'lane.archive', 'lane', p_lane_id::text, jsonb_build_object('reason', btrim(p_reason)));
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_apply_channels(p_event_id text, p_channels jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_clean jsonb := public.sanitize_project_channels(p_channels); v_old jsonb;
BEGIN
  IF v_clean IS NULL THEN RETURN public.project_err('CHANNELS_INVALID'); END IF;
  SELECT channels INTO v_old FROM event_projects WHERE event_id = p_event_id;
  UPDATE event_projects SET channels = v_clean WHERE event_id = p_event_id;
  -- The log keeps platforms and hosts only, never full links (a meeting link is a key to the room).
  PERFORM public.project_touch(p_event_id, 'channels.set', 'project', p_event_id, jsonb_build_object(
    'before', (SELECT coalesce(jsonb_agg(c->>'platform'), '[]'::jsonb) FROM jsonb_array_elements(v_old) c),
    'after', (SELECT coalesce(jsonb_agg(c->>'platform'), '[]'::jsonb) FROM jsonb_array_elements(v_clean) c)));
  RETURN jsonb_build_object('success', true, 'channels', v_clean);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_host_write(p_event_id text)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, true);
BEGIN
  IF v_err IS NOT NULL THEN RETURN v_err; END IF;
  IF NOT public.project_is_host(p_event_id) THEN RETURN 'NOT_AUTHORIZED'; END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.project_add_lane(p_event_id text, p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_host_write(p_event_id);
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  RETURN public.project_apply_lane_add(p_event_id, p_name);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_rename_lane(p_lane_id uuid, p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_event text := (SELECT event_id FROM public.event_project_lanes WHERE id = p_lane_id); v_err text;
BEGIN
  IF v_event IS NULL THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_host_write(v_event);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  RETURN public.project_apply_lane_rename(p_lane_id, p_name);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_archive_lane(p_lane_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_event text := (SELECT event_id FROM public.event_project_lanes WHERE id = p_lane_id); v_err text;
BEGIN
  IF v_event IS NULL THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_host_write(v_event);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  RETURN public.project_apply_lane_archive(p_lane_id, p_reason);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_set_channels(p_event_id text, p_channels jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_host_write(p_event_id);
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  RETURN public.project_apply_channels(p_event_id, p_channels);
END;
$$;

-- The channel list after one proposed change (NULL when the change no longer fits the current list).
CREATE OR REPLACE FUNCTION public.project_channels_after(p_current jsonb, p_kind text, p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v_url text := lower(btrim(coalesce(p_payload ->> 'url', '')));
BEGIN
  IF p_kind = 'channel_add' THEN RETURN coalesce(p_current, '[]'::jsonb) || jsonb_build_array(p_payload -> 'channel'); END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_current) c WHERE lower(c ->> 'url') = v_url) THEN RETURN NULL; END IF;
  IF p_kind = 'channel_remove' THEN
    RETURN coalesce((SELECT jsonb_agg(c) FROM jsonb_array_elements(p_current) c WHERE lower(c ->> 'url') <> v_url), '[]'::jsonb);
  END IF;
  RETURN (SELECT jsonb_agg(CASE WHEN lower(c ->> 'url') = v_url THEN p_payload -> 'channel' ELSE c END) FROM jsonb_array_elements(p_current) c);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_propose_change(p_event_id text, p_kind text, p_lane_id uuid DEFAULT NULL,
                                                          p_payload jsonb DEFAULT '{}'::jsonb, p_why text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_err text := public.project_guard(p_event_id, true); v_id uuid; v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF (public.project_me(p_event_id)).role IS DISTINCT FROM 'manager' THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF length(btrim(coalesce(p_why, ''))) NOT BETWEEN public.project_limit('reasonMin') AND public.project_limit('changeWhyMax') THEN
    RETURN public.project_err('REASON_REQUIRED');
  END IF;
  IF p_kind IN ('lane_add', 'lane_rename') AND length(btrim(coalesce(v_payload ->> 'name', ''))) NOT BETWEEN 1 AND public.project_limit('laneNameMax') THEN
    RETURN public.project_err('LANE_NAME_INVALID');
  ELSIF p_kind IN ('lane_rename', 'lane_archive')
        AND NOT EXISTS (SELECT 1 FROM event_project_lanes WHERE id = p_lane_id AND event_id = p_event_id AND archived_at IS NULL) THEN
    RETURN public.project_err('NOT_FOUND');
  ELSIF p_kind IN ('channel_add', 'channel_edit', 'channel_remove') THEN
    IF public.sanitize_project_channels(coalesce(public.project_channels_after(
         (SELECT channels FROM event_projects WHERE event_id = p_event_id), p_kind, v_payload), 'null'::jsonb)) IS NULL THEN
      RETURN public.project_err('CHANNELS_INVALID');
    END IF;
  ELSIF p_kind NOT IN ('lane_add', 'lane_rename', 'lane_archive') THEN
    RETURN public.project_err('INVALID_VALUE');
  END IF;
  INSERT INTO event_project_change_requests (event_id, kind, lane_id, payload, why, proposed_by)
  VALUES (p_event_id, p_kind, CASE WHEN p_kind IN ('lane_rename', 'lane_archive') THEN p_lane_id END, v_payload, btrim(p_why), auth.uid())
  RETURNING id INTO v_id;
  PERFORM public.project_touch(p_event_id, 'change.propose', 'change', v_id::text, jsonb_build_object('kind', p_kind));
  RETURN jsonb_build_object('success', true, 'request_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_review_change(p_request_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_r event_project_change_requests%ROWTYPE; v_err text; v_res jsonb; v_after jsonb;
BEGIN
  SELECT * INTO v_r FROM event_project_change_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_host_write(v_r.event_id);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF v_r.status <> 'pending' THEN RETURN public.project_err('NOT_PENDING'); END IF;
  IF p_approve IS NOT TRUE THEN
    IF NOT public.project_reason_ok(p_reason) THEN RETURN public.project_err('REASON_REQUIRED'); END IF;
    UPDATE event_project_change_requests SET status = 'declined', decided_by = auth.uid(), decided_at = now(), decision_reason = btrim(p_reason)
     WHERE id = p_request_id;
    PERFORM public.project_touch(v_r.event_id, 'change.decline', 'change', p_request_id::text, jsonb_build_object('kind', v_r.kind));
    RETURN jsonb_build_object('success', true, 'status', 'declined');
  END IF;
  -- Approve = apply now with the same checks as the Host's own action; if it no longer fits, nothing changes.
  v_res := CASE v_r.kind
    WHEN 'lane_add' THEN public.project_apply_lane_add(v_r.event_id, v_r.payload ->> 'name')
    WHEN 'lane_rename' THEN public.project_apply_lane_rename(v_r.lane_id, v_r.payload ->> 'name')
    WHEN 'lane_archive' THEN public.project_apply_lane_archive(v_r.lane_id, v_r.why)
    ELSE NULL END;
  IF v_r.kind LIKE 'channel_%' THEN
    v_after := public.project_channels_after((SELECT channels FROM event_projects WHERE event_id = v_r.event_id), v_r.kind, v_r.payload);
    v_res := CASE WHEN v_after IS NULL THEN public.project_err('CHANNELS_INVALID') ELSE public.project_apply_channels(v_r.event_id, v_after) END;
  END IF;
  IF NOT coalesce((v_res ->> 'success')::boolean, false) THEN RETURN v_res; END IF;
  UPDATE event_project_change_requests SET status = 'approved', decided_by = auth.uid(), decided_at = now(),
    decision_reason = nullif(btrim(coalesce(p_reason, '')), '') WHERE id = p_request_id;
  PERFORM public.project_touch(v_r.event_id, 'change.approve', 'change', p_request_id::text, jsonb_build_object('kind', v_r.kind));
  RETURN jsonb_build_object('success', true, 'status', 'approved', 'result', v_res);
END;
$$;

-- ================================================================== tasks
CREATE OR REPLACE FUNCTION public.project_upsert_task(p_event_id text, p_task_id uuid, p_lane_id uuid, p_title text,
                                                       p_assignee_id uuid DEFAULT NULL, p_due_date date DEFAULT NULL, p_status text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_err text := public.project_guard(p_event_id, true);
  v_host boolean; v_me event_project_members%ROWTYPE; v_t event_project_tasks%ROWTYPE;
  v_title text := btrim(coalesce(p_title, '')); v_changes jsonb := '{}'::jsonb;
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_host := public.project_is_host(p_event_id);
  v_me := public.project_me(p_event_id);
  IF p_task_id IS NOT NULL THEN
    SELECT * INTO v_t FROM event_project_tasks WHERE id = p_task_id AND event_id = p_event_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RETURN public.project_err('NOT_FOUND'); END IF;
  END IF;
  -- Host and Manager anywhere; a Lane lead only inside their own lane (both the task's current and new lane).
  IF NOT coalesce((v_host OR v_me.role = 'manager'
          OR (v_me.role = 'lane_lead' AND v_me.lane_id = p_lane_id AND (p_task_id IS NULL OR v_t.lane_id = v_me.lane_id))), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM event_project_lanes WHERE id = p_lane_id AND event_id = p_event_id AND archived_at IS NULL) THEN
    RETURN public.project_err('LANE_REQUIRED');
  END IF;
  IF length(v_title) NOT BETWEEN public.project_limit('taskTitleMin') AND public.project_limit('taskTitleMax') THEN
    RETURN public.project_err('TITLE_INVALID');
  END IF;
  IF p_assignee_id IS NOT NULL AND NOT public.project_is_participant(p_event_id, p_assignee_id) THEN
    RETURN public.project_err('ASSIGNEE_NOT_IN_PROJECT');
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('todo', 'doing', 'blocked', 'done') THEN RETURN public.project_err('INVALID_VALUE'); END IF;

  IF p_task_id IS NULL THEN
    INSERT INTO event_project_tasks (event_id, lane_id, title, assignee_id, due_date, status, created_by)
    VALUES (p_event_id, p_lane_id, v_title, p_assignee_id, p_due_date, coalesce(p_status, 'todo'), auth.uid())
    RETURNING * INTO v_t;
    PERFORM public.project_touch(p_event_id, 'task.create', 'task', v_t.id::text, jsonb_build_object('title', v_title));
  ELSE
    IF v_t.title <> v_title THEN v_changes := v_changes || jsonb_build_object('title', jsonb_build_array(v_t.title, v_title)); END IF;
    IF v_t.lane_id <> p_lane_id THEN v_changes := v_changes || jsonb_build_object('lane_id', jsonb_build_array(v_t.lane_id, p_lane_id)); END IF;
    IF v_t.assignee_id IS DISTINCT FROM p_assignee_id THEN v_changes := v_changes || jsonb_build_object('assignee_id', jsonb_build_array(v_t.assignee_id, p_assignee_id)); END IF;
    IF v_t.due_date IS DISTINCT FROM p_due_date THEN v_changes := v_changes || jsonb_build_object('due_date', jsonb_build_array(v_t.due_date, p_due_date)); END IF;
    IF p_status IS NOT NULL AND v_t.status <> p_status THEN v_changes := v_changes || jsonb_build_object('status', jsonb_build_array(v_t.status, p_status)); END IF;
    UPDATE event_project_tasks SET lane_id = p_lane_id, title = v_title, assignee_id = p_assignee_id, due_date = p_due_date,
      status = coalesce(p_status, status), updated_at = now() WHERE id = p_task_id RETURNING * INTO v_t;
    PERFORM public.project_touch(p_event_id, 'task.edit', 'task', v_t.id::text, jsonb_build_object('changes', v_changes));
  END IF;
  RETURN jsonb_build_object('success', true, 'task', to_jsonb(v_t) - 'deleted_at' - 'deleted_by' - 'delete_reason');
END;
$$;

CREATE OR REPLACE FUNCTION public.project_set_task_status(p_task_id uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_t event_project_tasks%ROWTYPE; v_err text; v_me event_project_members%ROWTYPE; v_host_id uuid; v_ev text;
BEGIN
  SELECT * INTO v_t FROM event_project_tasks WHERE id = p_task_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_t.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_me := public.project_me(v_t.event_id);
  IF NOT coalesce((public.project_is_host(v_t.event_id) OR v_me.role = 'manager' OR (v_me.role = 'lane_lead' AND v_me.lane_id = v_t.lane_id)
          OR v_t.assignee_id = auth.uid()), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  IF p_status NOT IN ('todo', 'doing', 'blocked', 'done') THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  IF v_t.status = p_status THEN RETURN jsonb_build_object('success', true, 'status', p_status, 'unchanged', true); END IF;
  UPDATE event_project_tasks SET status = p_status, updated_at = now() WHERE id = p_task_id;
  PERFORM public.project_touch(v_t.event_id, 'task.status', 'task', p_task_id::text, jsonb_build_object('from', v_t.status, 'to', p_status));
  -- Only "blocked" alerts at once (everything else waits for the daily digest, migration 211).
  IF p_status = 'blocked' THEN
    SELECT name INTO v_ev FROM events WHERE id = v_t.event_id;
    FOREACH v_host_id IN ARRAY public.project_host_ids(v_t.event_id) LOOP
      CONTINUE WHEN v_host_id = auth.uid();
      INSERT INTO notifications (recipient_id, kind, title, body, data)
      VALUES (v_host_id, 'project_blocked', 'Việc bị chặn', v_t.title || ' · ' || v_ev,
              jsonb_build_object('screen', 'event_project', 'event_id', v_t.event_id, 'task_id', p_task_id));
    END LOOP;
  END IF;
  RETURN jsonb_build_object('success', true, 'status', p_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_delete_task(p_task_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_t event_project_tasks%ROWTYPE; v_err text; v_me event_project_members%ROWTYPE;
BEGIN
  SELECT * INTO v_t FROM event_project_tasks WHERE id = p_task_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_t.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_me := public.project_me(v_t.event_id);
  IF NOT coalesce((public.project_is_host(v_t.event_id) OR v_me.role = 'manager' OR (v_me.role = 'lane_lead' AND v_me.lane_id = v_t.lane_id)), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  IF NOT public.project_reason_ok(p_reason) THEN RETURN public.project_err('REASON_REQUIRED'); END IF;
  UPDATE event_project_tasks SET deleted_at = now(), deleted_by = auth.uid(), delete_reason = btrim(p_reason) WHERE id = p_task_id;
  PERFORM public.project_trim_trash(v_t.event_id);
  PERFORM public.project_touch(v_t.event_id, 'task.delete', 'task', p_task_id::text, jsonb_build_object('reason', btrim(p_reason)));
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ================================================================== topics (no free chat)
CREATE OR REPLACE FUNCTION public.project_create_post(p_event_id text, p_type text, p_lane_id uuid, p_title text, p_body text DEFAULT '',
                                                       p_options text[] DEFAULT NULL, p_addressee_id uuid DEFAULT NULL, p_deadline date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_err text := public.project_guard(p_event_id, true);
  v_host boolean; v_me event_project_members%ROWTYPE; v_p event_project_posts%ROWTYPE;
  v_title text := btrim(coalesce(p_title, '')); v_body text := btrim(coalesce(p_body, ''));
  v_opts text[];
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_host := public.project_is_host(p_event_id);
  v_me := public.project_me(p_event_id);
  IF p_type NOT IN ('proposal', 'question', 'update', 'decision') THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  IF p_type = 'proposal' AND NOT coalesce((v_host OR v_me.role IN ('manager', 'finance', 'lane_lead')), false) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF p_type = 'decision' AND NOT coalesce((v_host OR v_me.role = 'manager' OR (v_me.role = 'lane_lead' AND v_me.lane_id = p_lane_id)), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM event_project_lanes WHERE id = p_lane_id AND event_id = p_event_id AND archived_at IS NULL) THEN
    RETURN public.project_err('LANE_REQUIRED');
  END IF;
  IF length(v_title) NOT BETWEEN public.project_limit('postTitleMin') AND public.project_limit('postTitleMax') THEN RETURN public.project_err('TITLE_INVALID'); END IF;
  IF length(v_body) > public.project_limit('postBodyMax') THEN RETURN public.project_err('BODY_TOO_LONG'); END IF;
  IF p_type = 'question' AND (p_addressee_id IS NULL OR p_addressee_id = auth.uid() OR NOT public.project_is_participant(p_event_id, p_addressee_id)) THEN
    RETURN public.project_err('ADDRESSEE_INVALID');
  END IF;
  IF p_type = 'proposal' THEN
    SELECT array_agg(btrim(o)) INTO v_opts FROM unnest(p_options) o WHERE btrim(o) <> '';
    IF coalesce(cardinality(v_opts), 0) NOT BETWEEN public.project_limit('proposalOptionsMin') AND public.project_limit('proposalOptionsMax')
       OR EXISTS (SELECT 1 FROM unnest(v_opts) o WHERE length(o) > public.project_limit('proposalOptionMax')) THEN
      RETURN public.project_err('OPTIONS_INVALID');
    END IF;
  END IF;
  INSERT INTO event_project_posts (event_id, lane_id, type, title, body, author_id, addressee_id, options, deadline, state)
  VALUES (p_event_id, p_lane_id, p_type, v_title, v_body, auth.uid(), CASE WHEN p_type = 'question' THEN p_addressee_id END,
          CASE WHEN p_type = 'proposal' THEN to_jsonb(v_opts) END, CASE WHEN p_type = 'proposal' THEN p_deadline END,
          CASE WHEN p_type = 'decision' THEN 'locked' ELSE 'open' END)
  RETURNING * INTO v_p;
  -- The author has seen their own update or decision.
  IF p_type IN ('update', 'decision') THEN INSERT INTO event_project_post_seen (post_id, user_id) VALUES (v_p.id, auth.uid()); END IF;
  PERFORM public.project_touch(p_event_id, 'post.create', 'post', v_p.id::text, jsonb_build_object('type', p_type));
  RETURN jsonb_build_object('success', true, 'post', public.project_post_json(v_p));
END;
$$;

CREATE OR REPLACE FUNCTION public.project_edit_post(p_post_id uuid, p_title text, p_body text DEFAULT '')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text; v_title text := btrim(coalesce(p_title, '')); v_body text := btrim(coalesce(p_body, ''));
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT coalesce((v_p.author_id = auth.uid() AND v_p.state = 'open' AND v_p.type <> 'decision'), false) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF NOT public.project_post_quiet(p_post_id) THEN RETURN public.project_err('ALREADY_ANSWERED'); END IF;
  IF length(v_title) NOT BETWEEN public.project_limit('postTitleMin') AND public.project_limit('postTitleMax') THEN RETURN public.project_err('TITLE_INVALID'); END IF;
  IF length(v_body) > public.project_limit('postBodyMax') THEN RETURN public.project_err('BODY_TOO_LONG'); END IF;
  UPDATE event_project_posts SET title = v_title, body = v_body, edited_at = now() WHERE id = p_post_id RETURNING * INTO v_p;
  PERFORM public.project_touch(v_p.event_id, 'post.edit', 'post', p_post_id::text);
  RETURN jsonb_build_object('success', true, 'post', public.project_post_json(v_p));
END;
$$;

-- One vote per person; voting for the same option again takes the vote back.
CREATE OR REPLACE FUNCTION public.project_vote(p_post_id uuid, p_option int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text; v_had smallint;
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF v_p.type <> 'proposal' OR v_p.state <> 'open' THEN RETURN public.project_err('NOT_OPEN'); END IF;
  IF p_option IS NULL OR p_option < 0 OR p_option >= jsonb_array_length(v_p.options) THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  SELECT option_index INTO v_had FROM event_project_post_votes WHERE post_id = p_post_id AND user_id = auth.uid();
  IF v_had = p_option THEN
    DELETE FROM event_project_post_votes WHERE post_id = p_post_id AND user_id = auth.uid();
  ELSE
    INSERT INTO event_project_post_votes (post_id, user_id, option_index) VALUES (p_post_id, auth.uid(), p_option)
    ON CONFLICT (post_id, user_id) DO UPDATE SET option_index = excluded.option_index, voted_at = now();
  END IF;
  PERFORM public.project_touch(v_p.event_id, 'post.vote', 'post', p_post_id::text);
  RETURN jsonb_build_object('success', true, 'my_vote', CASE WHEN v_had = p_option THEN NULL ELSE p_option END);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_mark_seen(p_post_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text;
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF v_p.type NOT IN ('update', 'decision') THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  INSERT INTO event_project_post_seen (post_id, user_id) VALUES (p_post_id, auth.uid()) ON CONFLICT DO NOTHING;
  IF FOUND THEN PERFORM public.project_touch(v_p.event_id, 'post.seen', 'post', p_post_id::text); END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_reply(p_post_id uuid, p_body text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text; v_body text := btrim(coalesce(p_body, '')); v_id uuid;
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF v_p.type NOT IN ('question', 'proposal') OR v_p.state <> 'open' THEN RETURN public.project_err('NOT_OPEN'); END IF;
  IF length(v_body) NOT BETWEEN 1 AND public.project_limit('replyMax') THEN RETURN public.project_err('BODY_INVALID'); END IF;
  IF (SELECT count(*) FROM event_project_post_replies WHERE post_id = p_post_id) >= public.project_limit('repliesMax') THEN
    RETURN public.project_err('REPLIES_FULL');
  END IF;
  INSERT INTO event_project_post_replies (post_id, author_id, body) VALUES (p_post_id, auth.uid(), v_body) RETURNING id INTO v_id;
  PERFORM public.project_touch(v_p.event_id, 'post.reply', 'post', p_post_id::text);
  RETURN jsonb_build_object('success', true, 'reply_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_resolve_post(p_post_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text; v_me event_project_members%ROWTYPE;
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_me := public.project_me(v_p.event_id);
  IF v_p.state <> 'open' OR v_p.type = 'update' THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF NOT coalesce((public.project_is_host(v_p.event_id) OR v_me.role = 'manager' OR (v_me.role = 'lane_lead' AND v_me.lane_id = v_p.lane_id)
          OR v_p.author_id = auth.uid() OR v_p.addressee_id = auth.uid()), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  UPDATE event_project_posts SET state = 'resolved', resolved_at = now(), resolved_by = auth.uid() WHERE id = p_post_id;
  PERFORM public.project_touch(v_p.event_id, 'post.resolve', 'post', p_post_id::text);
  RETURN jsonb_build_object('success', true);
END;
$$;

-- Settle a proposal: resolve it and record a locked Decision (the leading option unless one is named; ties go to the
-- first option). The client sends the decision title in the viewer's language; default = the option text.
CREATE OR REPLACE FUNCTION public.project_decide_proposal(p_post_id uuid, p_option int DEFAULT NULL, p_title text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text; v_me event_project_members%ROWTYPE; v_opt int; v_title text; v_d event_project_posts%ROWTYPE;
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_me := public.project_me(v_p.event_id);
  IF v_p.type <> 'proposal' OR v_p.state <> 'open' THEN RETURN public.project_err('NOT_OPEN'); END IF;
  IF NOT coalesce((public.project_is_host(v_p.event_id) OR v_me.role = 'manager' OR (v_me.role = 'lane_lead' AND v_me.lane_id = v_p.lane_id)), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  v_opt := coalesce(p_option, (SELECT i FROM generate_series(0, jsonb_array_length(v_p.options) - 1) i
    ORDER BY (SELECT count(*) FROM event_project_post_votes v WHERE v.post_id = p_post_id AND v.option_index = i) DESC, i LIMIT 1));
  IF v_opt < 0 OR v_opt >= jsonb_array_length(v_p.options) THEN RETURN public.project_err('INVALID_VALUE'); END IF;
  v_title := btrim(coalesce(nullif(btrim(coalesce(p_title, '')), ''), v_p.options ->> v_opt));
  IF length(v_title) NOT BETWEEN public.project_limit('postTitleMin') AND public.project_limit('postTitleMax') THEN RETURN public.project_err('TITLE_INVALID'); END IF;
  UPDATE event_project_posts SET state = 'resolved', resolved_at = now(), resolved_by = auth.uid() WHERE id = p_post_id;
  INSERT INTO event_project_posts (event_id, lane_id, type, title, body, author_id, state, source_post_id)
  VALUES (v_p.event_id, v_p.lane_id, 'decision', v_title, left(v_p.title, 280), auth.uid(), 'locked', p_post_id)
  RETURNING * INTO v_d;
  INSERT INTO event_project_post_seen (post_id, user_id) VALUES (v_d.id, auth.uid());
  PERFORM public.project_touch(v_p.event_id, 'post.decide', 'post', v_d.id::text, jsonb_build_object('from', p_post_id, 'option', v_opt));
  RETURN jsonb_build_object('success', true, 'decision', public.project_post_json(v_d));
END;
$$;

CREATE OR REPLACE FUNCTION public.project_delete_post(p_post_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_p event_project_posts%ROWTYPE; v_err text; v_me event_project_members%ROWTYPE;
BEGIN
  SELECT * INTO v_p FROM event_project_posts WHERE id = p_post_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_p.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  v_me := public.project_me(v_p.event_id);
  IF NOT coalesce((public.project_is_host(v_p.event_id) OR v_me.role = 'manager'
          OR (v_p.author_id = auth.uid() AND v_p.state = 'open' AND public.project_post_quiet(p_post_id))), false) THEN
    RETURN public.project_err('NOT_AUTHORIZED');
  END IF;
  IF NOT public.project_reason_ok(p_reason) THEN RETURN public.project_err('REASON_REQUIRED'); END IF;
  UPDATE event_project_posts SET deleted_at = now(), deleted_by = auth.uid(), delete_reason = btrim(p_reason) WHERE id = p_post_id;
  PERFORM public.project_trim_trash(v_p.event_id);
  PERFORM public.project_touch(v_p.event_id, 'post.delete', 'post', p_post_id::text, jsonb_build_object('reason', btrim(p_reason)));
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ================================================================== run-of-show (Day-of)
CREATE OR REPLACE FUNCTION public.project_upsert_ros_item(p_event_id text, p_item_id uuid, p_title text, p_owner_id uuid,
                                                           p_starts_at timestamptz, p_ends_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_err text := public.project_guard(p_event_id, true);
  v_title text := btrim(coalesce(p_title, '')); v_start timestamptz; v_r event_project_ros_items%ROWTYPE;
BEGIN
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT coalesce((public.project_is_host(p_event_id) OR (public.project_me(p_event_id)).role = 'manager'), false) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF length(v_title) NOT BETWEEN public.project_limit('rosTitleMin') AND public.project_limit('rosTitleMax') THEN RETURN public.project_err('TITLE_INVALID'); END IF;
  IF p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at < p_starts_at + make_interval(mins => public.project_limit('rosMinMinutes')) THEN
    RETURN public.project_err('TIME_INVALID');
  END IF;
  SELECT coalesce(e.starts_at, (e.event_date + coalesce(e.event_time, time '00:00')) AT TIME ZONE e.tz) INTO v_start FROM events e WHERE e.id = p_event_id;
  IF v_start IS NOT NULL AND (p_starts_at < v_start - make_interval(hours => public.project_limit('rosWindowBeforeStartHours'))
                              OR p_ends_at > v_start + make_interval(hours => public.project_limit('rosWindowAfterStartHours'))) THEN
    RETURN public.project_err('TIME_OUTSIDE_EVENT');
  END IF;
  IF p_owner_id IS NOT NULL AND NOT public.project_is_participant(p_event_id, p_owner_id) THEN RETURN public.project_err('OWNER_NOT_IN_PROJECT'); END IF;
  IF p_item_id IS NULL THEN
    INSERT INTO event_project_ros_items (event_id, title, owner_id, starts_at, ends_at, created_by)
    VALUES (p_event_id, v_title, p_owner_id, p_starts_at, p_ends_at, auth.uid()) RETURNING * INTO v_r;
    PERFORM public.project_touch(p_event_id, 'ros.create', 'ros', v_r.id::text);
  ELSE
    -- Editing while the day is running keeps a tick: the item stays done, at the time it was ticked.
    UPDATE event_project_ros_items SET title = v_title, owner_id = p_owner_id, starts_at = p_starts_at, ends_at = p_ends_at, updated_at = now()
     WHERE id = p_item_id AND event_id = p_event_id AND deleted_at IS NULL RETURNING * INTO v_r;
    IF NOT FOUND THEN RETURN public.project_err('NOT_FOUND'); END IF;
    PERFORM public.project_touch(p_event_id, 'ros.edit', 'ros', v_r.id::text);
  END IF;
  RETURN jsonb_build_object('success', true, 'item', to_jsonb(v_r) - 'deleted_at' - 'deleted_by' - 'delete_reason');
END;
$$;

-- Tick (or untick) an item. Everyone in the project may tick; the time is the server's, never the device's.
CREATE OR REPLACE FUNCTION public.project_tick_ros_item(p_item_id uuid, p_done boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_r event_project_ros_items%ROWTYPE; v_err text;
BEGIN
  SELECT * INTO v_r FROM event_project_ros_items WHERE id = p_item_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_r.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF (p_done AND v_r.done_at IS NOT NULL) OR (NOT p_done AND v_r.done_at IS NULL) THEN
    RETURN jsonb_build_object('success', true, 'done_at', v_r.done_at, 'unchanged', true);
  END IF;
  UPDATE event_project_ros_items SET done_at = CASE WHEN p_done THEN now() END, done_by = CASE WHEN p_done THEN auth.uid() END, updated_at = now()
   WHERE id = p_item_id RETURNING * INTO v_r;
  PERFORM public.project_touch(v_r.event_id, CASE WHEN p_done THEN 'ros.tick' ELSE 'ros.untick' END, 'ros', p_item_id::text);
  RETURN jsonb_build_object('success', true, 'done_at', v_r.done_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_delete_ros_item(p_item_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_r event_project_ros_items%ROWTYPE; v_err text;
BEGIN
  SELECT * INTO v_r FROM event_project_ros_items WHERE id = p_item_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_r.event_id, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT coalesce((public.project_is_host(v_r.event_id) OR (public.project_me(v_r.event_id)).role = 'manager'), false) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF NOT public.project_reason_ok(p_reason) THEN RETURN public.project_err('REASON_REQUIRED'); END IF;
  UPDATE event_project_ros_items SET deleted_at = now(), deleted_by = auth.uid(), delete_reason = btrim(p_reason) WHERE id = p_item_id;
  PERFORM public.project_trim_trash(v_r.event_id);
  PERFORM public.project_touch(v_r.event_id, 'ros.delete', 'ros', p_item_id::text, jsonb_build_object('reason', btrim(p_reason)));
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ================================================================== trash
CREATE OR REPLACE FUNCTION public.project_trash_event(p_kind text, p_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT CASE p_kind
    WHEN 'task' THEN (SELECT event_id FROM event_project_tasks WHERE id = p_id AND deleted_at IS NOT NULL)
    WHEN 'post' THEN (SELECT event_id FROM event_project_posts WHERE id = p_id AND deleted_at IS NOT NULL)
    WHEN 'ros' THEN (SELECT event_id FROM event_project_ros_items WHERE id = p_id AND deleted_at IS NOT NULL)
    WHEN 'lane' THEN (SELECT event_id FROM event_project_lanes WHERE id = p_id AND archived_at IS NOT NULL)
  END;
$$;

CREATE OR REPLACE FUNCTION public.project_restore(p_kind text, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_event text := public.project_trash_event(p_kind, p_id); v_err text; v_lane uuid; v_name text;
BEGIN
  IF v_event IS NULL THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_guard(v_event, true);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF NOT coalesce((public.project_is_host(v_event) OR (public.project_me(v_event)).role = 'manager'), false) THEN RETURN public.project_err('NOT_AUTHORIZED'); END IF;
  IF p_kind IN ('task', 'post') THEN
    v_lane := CASE p_kind WHEN 'task' THEN (SELECT lane_id FROM event_project_tasks WHERE id = p_id)
                          ELSE (SELECT lane_id FROM event_project_posts WHERE id = p_id) END;
    IF EXISTS (SELECT 1 FROM event_project_lanes WHERE id = v_lane AND archived_at IS NOT NULL) THEN RETURN public.project_err('RESTORE_LANE_FIRST'); END IF;
  END IF;
  IF p_kind = 'lane' THEN
    SELECT name INTO v_name FROM event_project_lanes WHERE id = p_id;
    IF (SELECT count(*) FROM event_project_lanes WHERE event_id = v_event AND archived_at IS NULL) >= public.project_limit('lanesMax') THEN
      RETURN public.project_err('LANES_FULL');
    END IF;
    IF EXISTS (SELECT 1 FROM event_project_lanes WHERE event_id = v_event AND archived_at IS NULL AND lower(btrim(name)) = lower(btrim(v_name))) THEN
      RETURN public.project_err('LANE_NAME_TAKEN');
    END IF;
    UPDATE event_project_lanes SET archived_at = NULL, archived_by = NULL, archive_reason = NULL WHERE id = p_id;
  ELSIF p_kind = 'task' THEN UPDATE event_project_tasks SET deleted_at = NULL, deleted_by = NULL, delete_reason = NULL, updated_at = now() WHERE id = p_id;
  ELSIF p_kind = 'post' THEN UPDATE event_project_posts SET deleted_at = NULL, deleted_by = NULL, delete_reason = NULL WHERE id = p_id;
  ELSE UPDATE event_project_ros_items SET deleted_at = NULL, deleted_by = NULL, delete_reason = NULL, updated_at = now() WHERE id = p_id;
  END IF;
  PERFORM public.project_touch(v_event, 'trash.restore', p_kind, p_id::text);
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.project_purge(p_kind text, p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_event text := public.project_trash_event(p_kind, p_id); v_err text;
BEGIN
  IF v_event IS NULL THEN RETURN public.project_err(CASE WHEN auth.uid() IS NULL THEN 'AUTH_REQUIRED' ELSE 'NOT_FOUND' END); END IF;
  v_err := public.project_host_write(v_event);
  IF v_err IS NOT NULL THEN RETURN public.project_err(v_err); END IF;
  IF p_kind = 'task' THEN DELETE FROM event_project_tasks WHERE id = p_id;
  ELSIF p_kind = 'post' THEN DELETE FROM event_project_posts WHERE id = p_id;
  ELSIF p_kind = 'ros' THEN DELETE FROM event_project_ros_items WHERE id = p_id;
  ELSE DELETE FROM event_project_lanes WHERE id = p_id;
  END IF;
  PERFORM public.project_touch(v_event, 'trash.purge', p_kind, p_id::text);
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ================================================================== who may call what
-- Supabase grants new functions to anon/authenticated by default. Every project function is revoked first; only the
-- client RPCs are granted back to authenticated. Helpers used inside RLS policies are granted too (policies run them
-- as the caller), and they reveal nothing beyond what the caller may read.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND (p.proname LIKE 'project\_%' OR p.proname IN (
       'get_event_project', 'get_event_project_posts', 'get_event_project_post', 'get_event_project_trash', 'get_event_project_ros',
       'get_my_event_projects', 'start_event_project', 'peek_project_invite', 'is_event_project_member', 'sanitize_project_channels'))
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION
  public.get_event_project(text, bigint), public.get_event_project_posts(text, timestamptz, int), public.get_event_project_post(uuid),
  public.get_event_project_trash(text), public.get_event_project_ros(text, bigint), public.get_my_event_projects(),
  public.start_event_project(text, text[]),
  public.project_create_invite(text, text, uuid, int), public.project_list_invites(text), public.project_revoke_invite(uuid),
  public.peek_project_invite(text), public.project_redeem_invite(text),
  public.project_set_member(uuid, text, uuid, boolean, boolean), public.project_remove_member(uuid, text), public.project_leave(text),
  public.project_add_lane(text, text), public.project_rename_lane(uuid, text), public.project_archive_lane(uuid, text),
  public.project_set_channels(text, jsonb), public.project_propose_change(text, text, uuid, jsonb, text),
  public.project_review_change(uuid, boolean, text),
  public.project_upsert_task(text, uuid, uuid, text, uuid, date, text), public.project_set_task_status(uuid, text),
  public.project_delete_task(uuid, text),
  public.project_create_post(text, text, uuid, text, text, text[], uuid, date), public.project_edit_post(uuid, text, text),
  public.project_vote(uuid, int), public.project_mark_seen(uuid), public.project_reply(uuid, text), public.project_resolve_post(uuid),
  public.project_decide_proposal(uuid, int, text), public.project_delete_post(uuid, text),
  public.project_upsert_ros_item(text, uuid, text, uuid, timestamptz, timestamptz), public.project_tick_ros_item(uuid, boolean),
  public.project_delete_ros_item(uuid, text),
  public.project_restore(text, uuid), public.project_purge(text, uuid),
  -- used by RLS policies:
  public.is_event_project_member(text), public.project_is_host(text)
TO authenticated;
