-- 175: date-of-birth correction requests.
-- A birthday is written once at sign-up and never overwritten by the client. When it is
-- wrong, the owner files a request here; a platform admin reviews it and applies it.
--  * request_dob_correction(p_dob, p_reason): owner, gate-checked, one pending at a time.
--  * get_my_dob_correction(): the owner's latest request (status only, never anyone else's).
--  * admin_list_dob_corrections(): admin-only queue with current vs requested date.
--  * admin_decide_dob_correction(p_id, p_approve, p_note): admin-only; approving rewrites
--    user_private_dob (source = 'admin_correction'). An admin cannot decide their own request.
-- Every decision is written to admin_action_log. No client table privileges.

CREATE TABLE IF NOT EXISTS public.dob_correction_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_dob date NOT NULL CHECK (requested_dob >= DATE '1900-01-01'),
  reason text NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 5 AND 500),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  decided_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decided_at timestamptz,
  decision_note text CHECK (decision_note IS NULL OR char_length(decision_note) <= 500),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS dob_correction_one_pending
  ON public.dob_correction_requests (user_id) WHERE status = 'pending';
ALTER TABLE public.dob_correction_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dob_correction_requests FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.request_dob_correction(p_dob date, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_current date;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF p_dob IS NULL OR p_dob < DATE '1900-01-01' OR p_dob > current_date THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_DOB');
  END IF;
  IF p_reason IS NULL OR char_length(btrim(p_reason)) < 5 OR char_length(btrim(p_reason)) > 500 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_REASON');
  END IF;
  SELECT date_of_birth INTO v_current FROM public.user_private_dob WHERE user_id = v_uid;
  IF v_current IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'NO_DOB_ON_FILE'); END IF;
  IF v_current = p_dob THEN RETURN jsonb_build_object('success', false, 'error', 'SAME_DOB'); END IF;
  IF EXISTS (SELECT 1 FROM public.dob_correction_requests WHERE user_id = v_uid AND status = 'pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_PENDING');
  END IF;
  INSERT INTO public.dob_correction_requests (user_id, requested_dob, reason)
  VALUES (v_uid, p_dob, btrim(p_reason));
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.request_dob_correction(date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_dob_correction(date, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_dob_correction()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE((
    SELECT jsonb_build_object('status', r.status, 'requested_dob', r.requested_dob,
                              'decision_note', r.decision_note, 'created_at', r.created_at)
      FROM public.dob_correction_requests r
     WHERE r.user_id = auth.uid() AND (SELECT public.account_gate_ok())
     ORDER BY r.created_at DESC LIMIT 1
  ), 'null'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.get_my_dob_correction() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_dob_correction() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_dob_corrections()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  RETURN jsonb_build_object('success', true, 'requests', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id', r.id, 'user_id', r.user_id, 'status', r.status, 'reason', r.reason,
      'requested_dob', r.requested_dob, 'current_dob', d.date_of_birth,
      'display_name', p.display_name, 'email', u.email,
      'created_at', r.created_at, 'decided_at', r.decided_at, 'decision_note', r.decision_note
    ) ORDER BY (r.status = 'pending') DESC, r.created_at DESC)
    FROM public.dob_correction_requests r
    JOIN auth.users u ON u.id = r.user_id
    LEFT JOIN public.profiles p ON p.id = r.user_id
    LEFT JOIN public.user_private_dob d ON d.user_id = r.user_id
  ), '[]'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_dob_corrections() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_dob_corrections() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_decide_dob_correction(p_id uuid, p_approve boolean, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_req public.dob_correction_requests%ROWTYPE;
  v_email text;
BEGIN
  IF v_admin IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  SELECT * INTO v_req FROM public.dob_correction_requests WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND'); END IF;
  IF v_req.status <> 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_PENDING'); END IF;
  IF v_req.user_id = v_admin THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_TARGET'); END IF;

  IF p_approve THEN
    UPDATE public.user_private_dob
       SET date_of_birth = v_req.requested_dob, source = 'admin_correction'
     WHERE user_id = v_req.user_id;
  END IF;
  UPDATE public.dob_correction_requests
     SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         decided_by = v_admin, decided_at = now(), decision_note = NULLIF(btrim(COALESCE(p_note, '')), '')
   WHERE id = p_id;

  SELECT email INTO v_email FROM auth.users WHERE id = v_req.user_id;
  INSERT INTO public.admin_action_log (actor_id, action, target_user_id, target_email)
  VALUES (v_admin, CASE WHEN p_approve THEN 'dob_correction_approved' ELSE 'dob_correction_rejected' END, v_req.user_id, v_email);
  RETURN jsonb_build_object('success', true);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_decide_dob_correction(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_decide_dob_correction(uuid, boolean, text) TO authenticated;
