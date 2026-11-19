-- 223 — signed-in users may read an organizer's public columns only; bank/tax/QR move behind a booker-scoped view.
--
-- Audit 2026-11-19 row 2 (P1). `organizers_select_public` (001:114-115) is `TO anon, authenticated USING (true)`, and
-- Supabase's default table SELECT grant let every signed-in account read every host's bank_name, bank_account_name,
-- bank_account_no, momo_phone, pay_qr_path, pay_qr_payload, pay_note, billing_address, tax_code, alert_phone and
-- telegram_chat_id — the whole host base scrapeable with a throwaway account. 185 closed this for anon only and left
-- authenticated's full SELECT in place as a product decision (185:20-21); this is that decision reversed.
--
-- What stays readable (everything else on the table): identity and public profile fields, plus owner_id/user_id.
-- owner_id/user_id are opaque relationship keys used by RLS policies across this schema (bookings_select_host,
-- refund_claims_select_host, events policies through is_event_host, and the client's own host lookups); revoking them
-- would make every policy subquery that joins organizers fail with "permission denied", so they are granted on
-- purpose. They are not financial or contact data.
--
-- Where the private columns went: `organizer_payouts`, one row per organizer, visible only to
--   * the organizer's own owner/user (host Settings > Payout, the pay-QR manager),
--   * a platform admin (event review's tax-code line),
--   * a guest who holds a pending or confirmed booking on one of that organizer's events (the payment screen).
-- The view is owned by the migration role, so it reads the table directly and each caller's rows are decided by the
-- WHERE clause on auth.uid(); it does not grant anything on `organizers` itself.
--
-- Client reads were moved to the view in the same change (web: loadPaymentBookings merges the payout row,
-- openPayout, PaymentQrManager, loadPendingEvents; iOS: loadPaymentBookings, openPayout, loadPayoutQR, loadPayQR,
-- the admin tax-code lookup). SECURITY DEFINER RPCs (save_organizer_payment, set_organizer_pay_qr,
-- get_organizer_profile, get_public_profile, payment documents, notifications) are unaffected by column grants.
--
-- Rollback: supabase/rollbacks/20261231000223_223_revert_organizers_column_grants.sql
-- Tests: supabase/tests/223_organizers_column_grants/run.sh (throwaway stack only).

BEGIN;

-- 1. Public columns stay readable; the bank/tax/QR set does not.
REVOKE SELECT ON public.organizers FROM authenticated;
GRANT SELECT (
  id, owner_id, user_id, name, ig_handle, instagram, bio, about, hosting_since,
  verified, verify_requested_at, pay_methods, refund_pledge, disputes_open, created_at,
  verify_sla_minutes, avatar_path, intro_long, social_links, organizer_type,
  avatar_r2_ref, share_card
) ON public.organizers TO authenticated;

-- 2. The private columns, for the three callers that genuinely need them.
CREATE OR REPLACE VIEW public.organizer_payouts AS
SELECT
  o.id,
  o.bank_name,
  o.bank_account_name,
  o.bank_account_no,
  o.momo_phone,
  o.pay_qr_path,
  o.pay_qr_payload,
  o.pay_note,
  o.billing_address,
  o.tax_code
FROM public.organizers o
WHERE o.owner_id = auth.uid()
   OR o.user_id = auth.uid()
   OR public.is_platform_admin()
   OR EXISTS (
     SELECT 1
       FROM public.bookings b
       JOIN public.events e ON e.id = b.event_id
      WHERE e.organizer_id = o.id
        AND b.user_id = auth.uid()
        AND b.status IN ('pending', 'confirmed', 'attended')
   );

COMMENT ON VIEW public.organizer_payouts IS
  'Audit 2026-11-19 row 2: an organizer''s bank/tax/QR columns for its host, a platform admin, or a guest holding a booking on one of its events.';

REVOKE ALL ON public.organizer_payouts FROM PUBLIC, anon;
GRANT SELECT ON public.organizer_payouts TO authenticated;

COMMIT;

-- Verification (after `supabase db push`, as a signed-in non-host through PostgREST):
--   GET /rest/v1/organizers?select=id,name&limit=1            -> 200
--   GET /rest/v1/organizers?select=bank_account_no&limit=1    -> 401/403 "permission denied"
--   GET /rest/v1/organizer_payouts?select=*                  -> only hosts you booked (or your own)
