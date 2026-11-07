-- Migration 141: ticket-holder contacts for the host's "cancel event" email draft.
--
-- When a host cancels an event they are offered a draft apology email addressed
-- to everyone who holds a ticket. The app needs each holder's name and email,
-- and the host cannot read other users' emails through RLS (profiles has no
-- email column; it lives in auth.users). This SECURITY DEFINER function hands
-- back ONLY that event's holders, ONLY to the event's organizer or an admin,
-- and nothing else about them.
--
-- Who counts: the bookings cancel_event() cancels (pending holds that have not
-- expired + confirmed). Before cancelling that is the live set; AFTER it, the
-- same people are the bookings cancel_event() stamped with the event's own
-- cancelled_at (same transaction, so the timestamps are identical). That is what
-- lets the host come back later and finish emailing everyone.
-- A gifted seat has two people to tell: the recipient (recipient_email) and the
-- purchaser, who owns the refund. Rows are de-duplicated by email.
--
-- Additive; reads only. Does not change cancel_event() or any status.

CREATE OR REPLACE FUNCTION public.get_event_ticket_holders(p_event text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ev events%ROWTYPE;
  v_rows jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT * INTO v_ev FROM events WHERE id = p_event OR slug = p_event OR key = p_event;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM organizers o WHERE o.id = v_ev.organizer_id AND (o.owner_id = auth.uid() OR o.user_id = auth.uid())
  ) AND NOT EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = auth.uid() AND p.role = 'admin'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  WITH affected AS (
    SELECT b.*
    FROM bookings b
    WHERE b.event_id = v_ev.id
      AND (
        b.status = 'confirmed'
        OR (b.status = 'pending' AND (b.expires_at IS NULL OR b.expires_at > now()))
        OR (v_ev.status = 'cancelled' AND b.status = 'cancelled' AND b.cancelled_at = v_ev.cancelled_at)
      )
  ),
  people AS (
    -- the person holding the seat (a gift's recipient, otherwise the booker)
    SELECT
      COALESCE(NULLIF(trim(a.recipient_name), ''), NULLIF(trim(pr.display_name), ''), '') AS name,
      lower(COALESCE(NULLIF(trim(a.recipient_email), ''), u.email)) AS email
    FROM affected a
    LEFT JOIN profiles pr ON pr.id = a.user_id
    LEFT JOIN auth.users u ON u.id = a.user_id
    UNION ALL
    -- a gift's purchaser also owns the money, so they hear about it too
    SELECT
      COALESCE(NULLIF(trim(pp.display_name), ''), '') AS name,
      lower(pu.email) AS email
    FROM affected a
    JOIN profiles pp ON pp.id = a.purchaser_id
    JOIN auth.users pu ON pu.id = a.purchaser_id
    WHERE a.gifted_at IS NOT NULL AND a.purchaser_id IS DISTINCT FROM a.user_id
  ),
  deduped AS (
    SELECT DISTINCT ON (email) email, name
    FROM people
    WHERE email IS NOT NULL AND email <> ''
    ORDER BY email, (name = '')
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name', name, 'email', email) ORDER BY name, email), '[]'::jsonb)
  INTO v_rows
  FROM deduped;

  RETURN jsonb_build_object('success', true, 'event_id', v_ev.id, 'holders', v_rows);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_event_ticket_holders(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_event_ticket_holders(text) TO authenticated;

COMMENT ON FUNCTION public.get_event_ticket_holders(text) IS
  'Name + email of everyone affected by cancelling an event. Organizer/admin only. Read-only.';
