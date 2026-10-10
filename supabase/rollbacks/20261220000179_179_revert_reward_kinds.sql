-- ROLLBACK for 179 (manual, NOT in the migration chain). Data-safe: no row is deleted.
-- Restores the previous function bodies (165; get_my_rewards as of 177). The widened schema is kept when it is in
-- use: if any partner_offer row (or NULL design_id) exists, DISABLE the flag instead:
--   update reward_feature_flags set enabled = false where flag = 'partner_offers';
BEGIN;
CREATE OR REPLACE FUNCTION public.redeem_reward(p_item_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid(); v_item public.reward_catalog%ROWTYPE; v_bal int; v_lid uuid;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  PERFORM public.rewards_lock_user(v_uid);
  SELECT * INTO v_item FROM public.reward_catalog WHERE code = p_item_code AND active;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND'); END IF;
  v_bal := public.rewards_balance(v_uid);
  IF EXISTS (SELECT 1 FROM public.reward_unlocks WHERE user_id = v_uid AND item_code = v_item.code) THEN
    RETURN jsonb_build_object('success', true, 'already_unlocked', true, 'balance', v_bal);
  END IF;
  IF v_bal < v_item.price THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_BALANCE', 'balance', v_bal, 'price', v_item.price);
  END IF;
  v_lid := public.rewards_add_entry(v_uid, 'redemption', -v_item.price, 'redeem:' || v_item.code, NULL, 'redemption',
                                    jsonb_build_object('item_code', v_item.code, 'design_id', v_item.design_id));
  IF v_lid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'TRY_AGAIN'); END IF;
  INSERT INTO public.reward_unlocks (user_id, item_code, ledger_id) VALUES (v_uid, v_item.code, v_lid);
  RETURN jsonb_build_object('success', true, 'balance', v_bal - v_item.price, 'design_id', v_item.design_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_unlocked_cosmetics()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  RETURN jsonb_build_object('success', true, 'design_ids', COALESCE((
    SELECT jsonb_agg(c.design_id ORDER BY c.sort) FROM public.reward_unlocks u JOIN public.reward_catalog c ON c.code = u.item_code
     WHERE u.user_id = v_uid), '[]'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_rewards()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid(); v_rules jsonb := public.rewards_rules(); v_counts jsonb;
  v_badges jsonb; v_hist jsonb; v_cat jsonb; v_paid int;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  v_counts := public.rewards_badge_counts(v_uid);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'code', d.code, 'title_vi', d.title_vi, 'title_en', d.title_en, 'desc_vi', d.desc_vi, 'desc_en', d.desc_en,
           'target', d.target,
           'progress', LEAST(public.rewards_badge_progress_of(d.code, v_counts), d.target),
           'earned', (b.badge_code IS NOT NULL AND b.revoked_at IS NULL),
           'earned_at', CASE WHEN b.revoked_at IS NULL THEN b.earned_at END) ORDER BY d.sort), '[]'::jsonb)
    INTO v_badges
    FROM public.reward_badge_defs d
    LEFT JOIN public.reward_user_badges b ON b.badge_code = d.code AND b.user_id = v_uid;

  SELECT COALESCE(jsonb_agg(h ORDER BY (h ->> 'created_at') DESC), '[]'::jsonb) INTO v_hist FROM (
    SELECT jsonb_build_object('id', l.id, 'type', l.entry_type, 'amount', l.amount, 'reason', l.reason,
                              'created_at', l.created_at, 'event_name', e.name, 'item_code', l.ref ->> 'item_code') AS h
      FROM public.reward_ledger l LEFT JOIN public.events e ON e.id = l.ref ->> 'event_id'
     WHERE l.user_id = v_uid ORDER BY l.created_at DESC LIMIT 40) x;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('code', c.code, 'kind', c.kind, 'design_id', c.design_id,
                                               'price', c.price, 'unlocked', u.user_id IS NOT NULL) ORDER BY c.sort), '[]'::jsonb)
    INTO v_cat FROM public.reward_catalog c
    LEFT JOIN public.reward_unlocks u ON u.item_code = c.code AND u.user_id = v_uid WHERE c.active;

  v_paid := public.rewards_month_paid_count(v_uid);

  RETURN jsonb_build_object(
    'success', true, 'balance', public.rewards_balance(v_uid), 'rules', v_rules,
    'streak', public.rewards_streak_of(v_uid), 'badges', v_badges, 'history', v_hist, 'catalog', v_cat,
    'attendance_paid_this_month', v_paid,
    'timezone_settings', public.rewards_tz_settings(v_uid));
END;
$$;

CREATE OR REPLACE FUNCTION public.profile_keychains_require_unlock()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.reward_catalog c WHERE c.design_id = NEW.design_id)
     AND NOT EXISTS (SELECT 1 FROM public.reward_unlocks u JOIN public.reward_catalog c ON c.code = u.item_code
                      WHERE u.user_id = NEW.user_id AND c.design_id = NEW.design_id) THEN
    RAISE EXCEPTION 'DESIGN_LOCKED' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_my_keychain(p_config jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  cur public.profile_keychains%ROWTYPE;
  v_enabled boolean; v_design text; v_anchor text; v_size text; v_motion boolean; v_asset uuid;
  v_tmp text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  IF NOT public.account_gate_ok() THEN RETURN jsonb_build_object('success', false, 'error', 'GATE_REQUIRED'); END IF;
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_CONFIG');
  END IF;

  SELECT * INTO cur FROM public.profile_keychains WHERE user_id = v_uid;
  v_enabled := COALESCE(cur.enabled, false);
  v_design  := COALESCE(cur.design_id, 'sky-star');
  v_anchor  := COALESCE(cur.anchor, 'top_right');
  v_size    := COALESCE(cur.size, 'm');
  v_motion  := COALESCE(cur.motion_enabled, true);
  v_asset   := cur.custom_asset_id;

  IF p_config ? 'enabled' THEN
    IF jsonb_typeof(p_config->'enabled') <> 'boolean' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_ENABLED'); END IF;
    v_enabled := (p_config->>'enabled')::boolean;
  END IF;
  IF p_config ? 'motionEnabled' THEN
    IF jsonb_typeof(p_config->'motionEnabled') <> 'boolean' THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_MOTION'); END IF;
    v_motion := (p_config->>'motionEnabled')::boolean;
  END IF;
  IF p_config ? 'designId' THEN
    IF jsonb_typeof(p_config->'designId') <> 'string' OR (p_config->>'designId') NOT IN (
      'sky-star','sky-moon','sky-cloud','love-heart','love-ribbon','love-bow',
      'bloom-flower','bloom-tulip','bloom-strawberry','bloom-lemon','cafe-cup','cafe-note','cafe-vinyl',
      'pals-cat','pals-bear','pals-paw','trip-ticket','trip-plane','trip-compass','trip-suitcase',
      'banbe-b','banbe-stub','banbe-spark','banbe-wave','rwd-comet','rwd-lantern','rwd-crown','custom') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_DESIGN');
    END IF;
    v_design := p_config->>'designId';
  END IF;
  IF p_config ? 'anchor' THEN
    IF jsonb_typeof(p_config->'anchor') <> 'string' OR (p_config->>'anchor') NOT IN ('top_left','top_right','bottom_left','bottom_right') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_ANCHOR');
    END IF;
    v_anchor := p_config->>'anchor';
  END IF;
  IF p_config ? 'size' THEN
    IF jsonb_typeof(p_config->'size') <> 'string' OR (p_config->>'size') NOT IN ('s','m','l') THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_SIZE');
    END IF;
    v_size := p_config->>'size';
  END IF;
  IF p_config ? 'customAssetId' THEN
    IF jsonb_typeof(p_config->'customAssetId') = 'null' THEN
      v_asset := NULL;
    ELSIF jsonb_typeof(p_config->'customAssetId') = 'string' THEN
      v_tmp := p_config->>'customAssetId';
      IF v_tmp !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_ASSET');
      END IF;
      v_asset := v_tmp::uuid;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_ASSET');
    END IF;
  END IF;

  -- A reward design must have been redeemed by this account.
  IF EXISTS (SELECT 1 FROM public.reward_catalog c WHERE c.design_id = v_design)
     AND NOT EXISTS (SELECT 1 FROM public.reward_unlocks u JOIN public.reward_catalog c ON c.code = u.item_code
                      WHERE u.user_id = v_uid AND c.design_id = v_design) THEN
    RETURN jsonb_build_object('success', false, 'error', 'DESIGN_LOCKED');
  END IF;

  -- A referenced asset must be a READY asset owned by the caller.
  IF v_asset IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.keychain_assets WHERE id = v_asset AND owner_id = v_uid AND status = 'ready'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ASSET_NOT_READY');
  END IF;
  IF v_design = 'custom' AND v_asset IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'CUSTOM_ASSET_REQUIRED');
  END IF;

  INSERT INTO public.profile_keychains (user_id, enabled, design_id, anchor, size, motion_enabled, custom_asset_id, updated_at)
  VALUES (v_uid, v_enabled, v_design, v_anchor, v_size, v_motion, v_asset, now())
  ON CONFLICT (user_id) DO UPDATE
    SET enabled = EXCLUDED.enabled, design_id = EXCLUDED.design_id, anchor = EXCLUDED.anchor, size = EXCLUDED.size,
        motion_enabled = EXCLUDED.motion_enabled, custom_asset_id = EXCLUDED.custom_asset_id, updated_at = now();

  RETURN jsonb_build_object('success', true, 'keychain', public.keychain_config_json(v_uid, false));
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.reward_catalog WHERE kind <> 'keychain_design' OR design_id IS NULL) THEN
    ALTER TABLE public.reward_catalog DROP CONSTRAINT IF EXISTS reward_catalog_design_required_for_keychain;
    ALTER TABLE public.reward_catalog DROP CONSTRAINT IF EXISTS reward_catalog_kind_check;
    ALTER TABLE public.reward_catalog ADD CONSTRAINT reward_catalog_kind_check CHECK (kind IN ('keychain_design'));
    ALTER TABLE public.reward_catalog ALTER COLUMN design_id SET NOT NULL;
  ELSE
    RAISE NOTICE 'partner_offer / design-less rows exist: schema left widened. Turn the partner_offers flag off instead.';
  END IF;
END $$;
COMMIT;
