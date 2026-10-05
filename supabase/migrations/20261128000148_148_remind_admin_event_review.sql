-- A host may remind the admins about an event that is waiting for review,
-- at most twice per event. The count is stored on the event; each reminder is an
-- in-app notification to every admin (same mechanism as the other review notices).

ALTER TABLE events ADD COLUMN IF NOT EXISTS admin_remind_count int NOT NULL DEFAULT 0;
ALTER TABLE events ADD COLUMN IF NOT EXISTS last_admin_reminded_at timestamptz;

CREATE OR REPLACE FUNCTION public.remind_admin_event_review(p_event_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_owner uuid;
  v_count int;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;

  SELECT COALESCE(o.owner_id, o.user_id) INTO v_owner FROM organizers o WHERE o.id = v_ev.organizer_id;
  IF v_owner IS DISTINCT FROM auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_ev.status <> 'review' THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_PENDING');
  END IF;

  IF v_ev.admin_remind_count >= 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'REMIND_LIMIT_REACHED', 'remind_count', v_ev.admin_remind_count);
  END IF;

  UPDATE events SET admin_remind_count = admin_remind_count + 1, last_admin_reminded_at = now()
  WHERE id = p_event_id RETURNING admin_remind_count INTO v_count;

  INSERT INTO notifications (recipient_id, kind, title, body, data)
  SELECT p.id, 'event_review_reminder', 'Nhắc duyệt sự kiện',
         'Người tổ chức nhắc bạn duyệt sự kiện "' || v_ev.name || '" (lần ' || v_count || '/2).',
         jsonb_build_object('event_id', p_event_id, 'remind_count', v_count)
  FROM profiles p WHERE p.role = 'admin';

  RETURN jsonb_build_object('success', true, 'remind_count', v_count);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.remind_admin_event_review(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.remind_admin_event_review(text) TO authenticated;
