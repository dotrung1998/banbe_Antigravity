-- Migration 161: admin "Test accounts" — search accounts by display name.
-- Additive to 159 (already applied). Same authorization as the other admin_*
-- phone-exemption RPCs: platform admin only, decided server-side. Returns at
-- most 10 matches with just enough to pick one (id, email, name, role) — no
-- phone, DOB or other private data. The caller then uses the existing
-- admin_phone_exempt_lookup(email) for the full status.
CREATE OR REPLACE FUNCTION public.admin_phone_exempt_search(p_query text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_q text := trim(coalesce(p_query, ''));
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() OR NOT public.account_gate_ok() THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;
  IF length(v_q) < 2 THEN
    RETURN jsonb_build_object('success', true, 'results', '[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('success', true, 'results', coalesce((
    SELECT jsonb_agg(r) FROM (
      SELECT u.id AS user_id, u.email, p.display_name, p.role
        FROM public.profiles p
        JOIN auth.users u ON u.id = p.id
       WHERE p.display_name ILIKE '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
       ORDER BY p.display_name
       LIMIT 10
    ) r), '[]'::jsonb));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_phone_exempt_search(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_phone_exempt_search(text) TO authenticated;
