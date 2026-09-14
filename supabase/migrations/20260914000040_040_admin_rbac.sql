-- Migration: designate banbetestadmin@gmail.com as the super admin, and
-- close the one real RBAC gap this repo had — admin read access to the
-- receipt image behind a dispute.
--
-- ---------------------------------------------------------------------------
-- WHAT ALREADY EXISTS (not reinvented here)
-- ---------------------------------------------------------------------------
-- `public.profiles.role` already exists (migration 001), already NOT NULL
-- DEFAULT 'participant', and is already the app's one source of truth for
-- role — both clients load it into global state on sign-in (GocContext.jsx's
-- `accountType`, AppState.swift's `accountType`, fed from `Profile.role`) and
-- every admin-only RPC/RLS policy in this schema already checks it
-- (`is_platform_admin()`, `resolve_dispute()`, `v_disputes`, `bookings_select_
-- admin`, `dispute_threads`/`dispute_messages`, `payment_audit_select_party`).
-- The values are 'participant' | 'organizer' | 'admin' — NOT 'user' |
-- 'host' | 'admin' as a fresh design might pick; matching a new naming
-- scheme to this migration instead of the other way around would silently
-- break every one of those existing checks, so this migration works with
-- the values that are actually live rather than renaming them.
--
-- The Web/iOS "unified login, fetch role after sign-in, gate an admin
-- entry point" flow this ticket describes is also already built:
-- GocContext.jsx's syncUser()/AppState.swift's applySession() already fetch
-- `profiles.role` right after sign-in on both platforms, Account.jsx already
-- shows an admin-only "Chờ xử lý tranh chấp"/dispute-queue row gated on
-- `s.accountType === 'admin'` (opening the existing Disputes.jsx screen —
-- this repo's admin dashboard), and this same session is adding the iOS
-- counterpart (AdminDashboardView.swift) directly, client-side, alongside
-- this migration. There is no server-side routing to protect here — this
-- is a client-state SPA (see src/App.jsx), not a Next.js app with URL
-- routes, so "/admin" is a `screen` value gated the same way every other
-- screen transition already is (openDisputes() itself, unchanged), not a
-- literal path.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS MIGRATION ACTUALLY ADDS
-- ---------------------------------------------------------------------------
-- 1. The specific admin account, both for whoever already signed up under
--    that email and for any future signup under it.
-- 2. The one place an admin genuinely couldn't reach data the Admin
--    Dashboard needs: the 'pay-proof' storage bucket's read policy checked
--    only the booking's own guest or its event's organizer — never
--    `is_platform_admin()` — so an admin reviewing a dispute could load
--    every OTHER field (reference, transaction id, chat, audit trail) but
--    never actually see the receipt image itself.

-- 1a. Whoever already has this email in auth.users gets role='admin' now.
UPDATE public.profiles p
SET role = 'admin'
FROM auth.users u
WHERE p.id = u.id AND lower(u.email) = 'banbetestadmin@gmail.com' AND p.role <> 'admin';

UPDATE public.email_registrations
SET role = 'admin', updated_at = now()
WHERE email = 'banbetestadmin@gmail.com' AND role <> 'admin';

-- 1b. handle_new_user() (migration 023's version was the last to touch it)
-- always inserted role='participant' regardless of who was signing up —
-- extended here, preserving everything else it already does (referral
-- code, email_registrations), to auto-admin this one address on signup.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := CASE WHEN lower(COALESCE(NEW.email, '')) = 'banbetestadmin@gmail.com'
                       THEN 'admin' ELSE 'participant' END;
BEGIN
    INSERT INTO public.profiles (id, display_name, phone, locale, role, referral_code)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
      COALESCE(NEW.phone, ''),
      'vi',
      v_role,
      public.generate_referral_code()
    )
    ON CONFLICT (id) DO NOTHING;

    IF NEW.email IS NOT NULL THEN
      INSERT INTO public.email_registrations (email, role, auth_user_id)
      VALUES (lower(NEW.email), v_role, NEW.id)
      ON CONFLICT (email) DO UPDATE SET
        auth_user_id = EXCLUDED.auth_user_id,
        updated_at = now();
    END IF;
    RETURN NEW;
END;
$$;

-- 2. Admin bypass on the 'pay-proof' bucket's read policy — same bypass
--    every other dispute-relevant table already grants is_platform_admin().
DROP POLICY IF EXISTS "pay_proof_read" ON storage.objects;
CREATE POLICY "pay_proof_read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'pay-proof' AND (
    public.is_platform_admin()
    OR EXISTS (
      SELECT 1 FROM public.bookings b
      JOIN public.events e ON e.id = b.event_id
      LEFT JOIN public.organizers o ON o.id = e.organizer_id
      WHERE b.id::text = split_part((objects).name, '/', 1)
        AND (b.user_id = auth.uid() OR o.owner_id = auth.uid() OR o.user_id = auth.uid())
    )
  )
);
