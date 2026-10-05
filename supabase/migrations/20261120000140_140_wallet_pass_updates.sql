-- Migration 140: Apple Wallet pass update service.
--
-- Apple's PassKit web service lets a pass that is already in someone's Wallet
-- be replaced or voided later (for example when the ticket is gifted and the
-- purchaser's QR stops being valid). It needs the server to remember:
--   * wallet_passes               one row per issued pass: the design the holder
--                                 chose (so the refreshed pass looks the same) and
--                                 a hash of the ticket state the pass last showed,
--   * wallet_pass_registrations   which devices hold it, and the APNs push token
--                                 Wallet gave us for each.
--
-- Both are read and written ONLY by the Vercel functions under api/wallet*
-- using the service role. RLS is enabled with no policies on purpose: nothing a
-- signed-in user's JWT can reach, since the push tokens and banner images are
-- not theirs to enumerate. Additive; touches nothing from 001 to 139.

CREATE TABLE IF NOT EXISTS public.wallet_passes (
  serial_number   uuid PRIMARY KEY REFERENCES public.bookings(id) ON DELETE CASCADE,
  pass_type_id    text NOT NULL,
  owner_id        uuid,
  background      text NOT NULL DEFAULT '#1C1C1E',
  foreground      text NOT NULL DEFAULT '#FFFFFF',
  label           text NOT NULL DEFAULT '#FFFFFF',
  banner_png_b64  text,
  state_hash      text NOT NULL DEFAULT '',
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.wallet_pass_registrations (
  device_id      text NOT NULL,
  serial_number  uuid NOT NULL REFERENCES public.wallet_passes(serial_number) ON DELETE CASCADE,
  push_token     text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, serial_number)
);

CREATE INDEX IF NOT EXISTS idx_wallet_pass_registrations_serial ON public.wallet_pass_registrations(serial_number);

ALTER TABLE public.wallet_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_pass_registrations ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.wallet_passes IS
  'Issued Apple Wallet passes: chosen design + hash of the ticket state last shown. Service-role only (no RLS policies).';
COMMENT ON TABLE public.wallet_pass_registrations IS
  'Devices holding a pass and their APNs push tokens. Service-role only (no RLS policies).';
