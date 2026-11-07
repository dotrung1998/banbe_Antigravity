-- DRAFT — NOT IN CHAIN. Rollback for DRAFT_NOT_IN_CHAIN_sponsors_offers_redemptions.sql.
-- Removes the new objects ONLY while every new table is empty; refuses (raises) otherwise. Primary switch is the flags:
--   update reward_feature_flags set enabled = false where flag in ('partner_confirm', 'partner_offers');
BEGIN;
DO $$
DECLARE t text; n bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY['reward_redemptions', 'reward_settlements', 'reward_offers', 'sponsor_campaigns', 'sponsor_staff', 'sponsors'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
      IF n > 0 THEN RAISE EXCEPTION 'refusing rollback: public.% has % row(s); turn the flags off instead', t, n; END IF;
    END IF;
  END LOOP;
END $$;
DROP FUNCTION IF EXISTS public.partner_confirm_redemption(text);
DROP TABLE IF EXISTS public.reward_redemptions;
DROP TABLE IF EXISTS public.reward_settlements;
DROP TABLE IF EXISTS public.reward_offers;
DROP FUNCTION IF EXISTS public.reward_offers_require_partner_catalog();
DROP TABLE IF EXISTS public.sponsor_campaigns;
DROP TABLE IF EXISTS public.sponsor_staff;
DROP TABLE IF EXISTS public.sponsors;
DELETE FROM public.reward_feature_flags WHERE flag = 'partner_confirm';
COMMIT;
