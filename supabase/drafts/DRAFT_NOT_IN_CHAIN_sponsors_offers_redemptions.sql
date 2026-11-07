-- ============================================================================================================
-- DRAFT — NOT IN CHAIN — DO NOT APPLY.  Phase 0 step 4 (docs/rewards-research.md §5.2, §5.3 option 1, §5.6).
-- Not a migration: no timestamp, lives outside supabase/migrations, so `supabase db push` cannot run it.
-- Tested only inside a rolled-back transaction on a throwaway local container (supabase/_localtest/17_*).
-- ============================================================================================================
--
-- WHAT IT IS
--   The data model for partner-sponsored offers where the PARTNER issues and honours the offer and banbe holds no
--   money and issues no vouchers (research §5.3 option 1). Coins keep no cash value: nothing here converts coins to
--   money, sells coins, transfers them or pays cash. price_coins may be 0 (offer unlocked by badge/attendance).
--
-- HOW IT FITS WITH 179 (checked against the applied chain up to 179)
--   * 179 made reward_catalog.kind allow 'partner_offer' and added title_/desc_ columns; get_my_rewards().offers is
--     read from reward_catalog WHERE kind='partner_offer' AND active, only when reward_feature_flags 'partner_offers'
--     is on. It does NOT read a reward_offers table (none exists in the chain).
--   * So reward_offers here EXTENDS that listing row 1:1 (catalog_code UNIQUE -> reward_catalog.code) instead of
--     duplicating it. Titles/descriptions/price shown to users stay in reward_catalog; reward_offers adds what a
--     real offer needs (campaign, stock, terms, validity, confirmation method). No name clashes: none of the six
--     tables/functions below exist in migrations 001-179. This draft alters no existing table and no existing
--     function. A LATER migration (not here) must update get_my_rewards().offers to join reward_offers for
--     validity/stock before any offer is shown as redeemable.
--   * 179's redeem_reward keeps returning NOT_AVAILABLE for partner_offer; issuing a redemption (coin charge +
--     token) is a separate RPC that does not exist yet (Phase 1). This draft only has the tables and the partner's
--     "confirm one code" stub.
--
-- PRIVACY (research §5.6)
--   * RLS ON, NO table grants to anon/authenticated (pattern of 165:191-201). Doors are SECURITY DEFINER RPCs only.
--   * No RPC lists users. The partner stub takes a code and returns ONLY {offer title, redeemed_at}: no user id,
--     name, phone, email, event history, coin balance.
--   * reward_redemptions.user_id exists because a redemption is a transactional record the app must show the owner
--     and enforce limits on; it is never exposed to partners. It is NOT an activity log: no views/impressions are
--     recorded here (that is step 5, de-identified).
--   * The code is stored only as a SHA-256 hash.
--
-- ACTIVATION CONDITIONS (all required before promoting this to a migration and turning anything on)
--   1. Lawyer review of research §6.5 questions 1-3, 5, 6 and the policy changes (docs/policy-rewards-draft.md).
--   2. At least one willing partner with a written agreement (responsibility for the offer is the partner's).
--   3. A rate limit / lockout for partner_confirm_redemption (code guessing) and an issuing RPC with per-user
--      limits, stock locking and token generation (Phase 1) — NOT in this draft.
--   4. Admin tooling to create sponsors/campaigns/offers and to void redemptions.
--   5. Feature flags below stay OFF until 1-4 are done; turn on in staging first.
--
-- RISKS
--   * partner_confirm_redemption is a code-guessing surface once on. Stub is inert behind the flag and returns the
--     same CODE_NOT_FOUND for unknown / other-sponsor codes, but has NO lockout yet.
--   * sponsor_staff is a sixth table (not in §5.2) — needed to authorise the partner stub; open decision.
--   * reward_redemptions.ledger_id links a coin charge; a refund path for void redemptions is undefined.
--   * Offer terms/validity are legal content (VN promotion rules, US contest rules): data only here.
--
-- ROLLBACK (data-safe): DRAFT_NOT_IN_CHAIN_sponsors_offers_redemptions_rollback.sql drops the new objects ONLY
--   while every new table is empty and refuses otherwise. Primary switch is the flags (set false), not DROP.
--   Nothing existing is altered, so there is nothing to restore.
-- ============================================================================================================

CREATE TABLE IF NOT EXISTS public.sponsors (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name    text NOT NULL CHECK (length(btrim(legal_name)) > 0),
  country       text NOT NULL CHECK (country IN ('US', 'VN')),
  kind          text NOT NULL CHECK (kind IN ('host', 'venue', 'brand')),
  organizer_id  text REFERENCES public.organizers(id) ON DELETE SET NULL,   -- a host/venue that is also a banbe organizer
  status        text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'suspended', 'ended')),
  contact_ref   text NOT NULL DEFAULT '',        -- pointer to an off-platform contact record, not a personal email/phone
  contract_ref  text NOT NULL DEFAULT '',
  starts_on     date,
  ends_on       date,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on)
);

-- Who may confirm codes for a sponsor (authorises the partner stub). Staff see nothing about users.
CREATE TABLE IF NOT EXISTS public.sponsor_staff (
  sponsor_id uuid NOT NULL REFERENCES public.sponsors(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (sponsor_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.sponsor_campaigns (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sponsor_id             uuid NOT NULL REFERENCES public.sponsors(id) ON DELETE CASCADE,
  name                   text NOT NULL,
  starts_at              timestamptz NOT NULL,
  ends_at                timestamptz NOT NULL,
  budget_cap_redemptions int CHECK (budget_cap_redemptions IS NULL OR budget_cap_redemptions > 0),
  per_user_limit         int NOT NULL DEFAULT 1 CHECK (per_user_limit > 0),
  country_codes          text[] NOT NULL DEFAULT '{}' CHECK (country_codes <@ ARRAY['US', 'VN']),
  eligibility            jsonb NOT NULL DEFAULT '{}'::jsonb,   -- e.g. {"badge":"regular","min_checkins":3}; evaluated server-side
  status                 text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'running', 'paused', 'ended')),
  created_at             timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS sponsor_campaigns_sponsor ON public.sponsor_campaigns (sponsor_id, status);

CREATE TABLE IF NOT EXISTS public.reward_offers (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id         uuid NOT NULL REFERENCES public.sponsor_campaigns(id) ON DELETE CASCADE,
  catalog_code        text NOT NULL UNIQUE REFERENCES public.reward_catalog(code),   -- the listing row 179 reads (must be kind partner_offer)
  terms_vi            text NOT NULL DEFAULT '',
  terms_en            text NOT NULL DEFAULT '',
  required_badge_code text REFERENCES public.reward_badge_defs(code),                -- unlock by badge instead of paying coins
  stock_total         int CHECK (stock_total IS NULL OR stock_total >= 0),
  confirm_method      text NOT NULL CHECK (confirm_method IN ('partner_scan', 'partner_code', 'show_screen')),
  redeem_window_hours int NOT NULL DEFAULT 48 CHECK (redeem_window_hours BETWEEN 1 AND 720),
  valid_from          timestamptz,
  valid_until         timestamptz,
  region              text NOT NULL DEFAULT '',
  status              text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'live', 'paused', 'ended')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);

-- The catalog row must be a partner offer (a keychain design can never be an offer).
CREATE OR REPLACE FUNCTION public.reward_offers_require_partner_catalog()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.reward_catalog c WHERE c.code = NEW.catalog_code AND c.kind = 'partner_offer') THEN
    RAISE EXCEPTION 'catalog_code must reference a partner_offer catalog row' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS reward_offers_require_partner_catalog ON public.reward_offers;
CREATE TRIGGER reward_offers_require_partner_catalog BEFORE INSERT OR UPDATE OF catalog_code ON public.reward_offers
  FOR EACH ROW EXECUTE FUNCTION public.reward_offers_require_partner_catalog();

-- Banbe-to-partner settlement (fees flow from the PARTNER to banbe; users pay nothing).
CREATE TABLE IF NOT EXISTS public.reward_settlements (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id       uuid NOT NULL REFERENCES public.sponsor_campaigns(id) ON DELETE CASCADE,
  period_start      date NOT NULL,
  period_end        date NOT NULL,
  redemptions_count int NOT NULL DEFAULT 0 CHECK (redemptions_count >= 0),
  invoice_ref       text NOT NULL DEFAULT '',
  status            text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'issued', 'paid', 'void')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end >= period_start)
);

CREATE TABLE IF NOT EXISTS public.reward_redemptions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,   -- never exposed to partners
  offer_id       uuid NOT NULL REFERENCES public.reward_offers(id),
  ledger_id      uuid UNIQUE REFERENCES public.reward_ledger(id),                  -- the coin charge, if price_coins > 0
  status         text NOT NULL DEFAULT 'issued' CHECK (status IN ('issued', 'redeemed', 'expired', 'void')),
  code_hash      text NOT NULL UNIQUE,                                             -- sha256 hex of the normalised code
  issued_at      timestamptz NOT NULL DEFAULT now(),
  expires_at     timestamptz NOT NULL,
  redeemed_at    timestamptz,
  redeemed_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,           -- the partner staff account that confirmed
  settlement_id  uuid REFERENCES public.reward_settlements(id),
  CHECK ((status = 'redeemed') = (redeemed_at IS NOT NULL)),
  CHECK (expires_at > issued_at)
);
CREATE INDEX IF NOT EXISTS reward_redemptions_user  ON public.reward_redemptions (user_id, offer_id);
CREATE INDEX IF NOT EXISTS reward_redemptions_offer ON public.reward_redemptions (offer_id, status);

-- Flags (reward_feature_flags exists since 179). OFF.
INSERT INTO public.reward_feature_flags (flag, enabled) VALUES ('partner_confirm', false) ON CONFLICT (flag) DO NOTHING;

-- No client access to any new table: the RPC below is the only door (pattern of 165:191-201).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['sponsors', 'sponsor_staff', 'sponsor_campaigns', 'reward_offers', 'reward_settlements', 'reward_redemptions']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON public.%I FROM anon, authenticated, PUBLIC', t);
  END LOOP;
END $$;

-- ------------------------------------------------------------------------------------------------------------
-- STUB: a partner confirms ONE code. Not wired to any UI. Inert while the 'partner_confirm' flag is off.
-- Returns only the offer title and the confirmation time; never anything about the user. Unknown code, a code of
-- another sponsor, and a caller who is not staff all answer CODE_NOT_FOUND (no probing of which codes exist).
-- No lockout yet (see RISKS).
-- ------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.partner_confirm_redemption(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_hash text; r public.reward_redemptions%ROWTYPE; v_offer public.reward_offers%ROWTYPE;
        v_camp public.sponsor_campaigns%ROWTYPE; v_title jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT COALESCE((SELECT f.enabled FROM public.reward_feature_flags f WHERE f.flag = 'partner_confirm'), false) THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE');
  END IF;
  IF p_code IS NULL OR length(btrim(p_code)) < 6 OR length(p_code) > 64 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CODE_NOT_FOUND');
  END IF;
  v_hash := encode(sha256(convert_to(upper(btrim(p_code)), 'UTF8')), 'hex');

  SELECT * INTO r FROM public.reward_redemptions WHERE code_hash = v_hash FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'CODE_NOT_FOUND'); END IF;
  SELECT * INTO v_offer FROM public.reward_offers WHERE id = r.offer_id;
  SELECT * INTO v_camp FROM public.sponsor_campaigns WHERE id = v_offer.campaign_id;
  -- the caller must be active staff of the sponsor that owns this offer
  IF NOT EXISTS (SELECT 1 FROM public.sponsor_staff s JOIN public.sponsors sp ON sp.id = s.sponsor_id
                  WHERE s.sponsor_id = v_camp.sponsor_id AND s.user_id = v_uid AND s.status = 'active' AND sp.status = 'active') THEN
    RETURN jsonb_build_object('success', false, 'error', 'CODE_NOT_FOUND');
  END IF;
  IF v_camp.status <> 'running' OR v_offer.status <> 'live' THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_AVAILABLE'); END IF;
  IF r.status = 'redeemed' THEN RETURN jsonb_build_object('success', false, 'error', 'ALREADY_REDEEMED'); END IF;
  IF r.status <> 'issued' THEN RETURN jsonb_build_object('success', false, 'error', 'CODE_NOT_FOUND'); END IF;   -- void / expired
  IF r.expires_at <= now() THEN
    UPDATE public.reward_redemptions SET status = 'expired' WHERE id = r.id;
    RETURN jsonb_build_object('success', false, 'error', 'CODE_EXPIRED');
  END IF;

  UPDATE public.reward_redemptions SET status = 'redeemed', redeemed_at = now(), redeemed_by = v_uid WHERE id = r.id;
  SELECT jsonb_build_object('vi', c.title_vi, 'en', c.title_en) INTO v_title FROM public.reward_catalog c WHERE c.code = v_offer.catalog_code;
  RETURN jsonb_build_object('success', true, 'offer_title', v_title, 'redeemed_at', now());
END;
$$;
REVOKE ALL ON FUNCTION public.partner_confirm_redemption(text) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.partner_confirm_redemption(text) TO authenticated;
