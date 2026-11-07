-- Migration: Fix organizer role enforcement on signup and event creation

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, phone, locale, role)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
        COALESCE(NEW.phone, ''),
        'vi',
        CASE trim(NEW.raw_user_meta_data->>'account_type')
          WHEN 'organizer' THEN 'organizer'
          WHEN 'admin' THEN 'admin'
          ELSE 'participant'
        END
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();

CREATE OR REPLACE FUNCTION create_event_draft(
  p_name text, p_category text, p_description text, p_location text,
  p_event_date date, p_event_time time, p_price_vnd bigint, p_capacity int,
  p_organizer_name text, p_instagram text DEFAULT '', p_about text DEFAULT ''
) RETURNS events LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer organizers%ROWTYPE;
  v_event events%ROWTYPE;
  v_org_id text;
  v_event_id text;
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_name IS NULL OR length(trim(p_name)) = 0 OR p_capacity IS NULL OR p_capacity < 1 THEN RAISE EXCEPTION 'INVALID_EVENT'; END IF;

  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('organizer', 'admin') THEN
    RAISE EXCEPTION 'FORBIDDEN: Only organizers can create events.';
  END IF;

  SELECT * INTO v_organizer FROM organizers WHERE owner_id = auth.uid() OR user_id = auth.uid() ORDER BY created_at LIMIT 1;
  IF NOT FOUND THEN
    v_org_id := 'org_' || substr(md5(gen_random_uuid()::text), 1, 8);
    INSERT INTO organizers(id, owner_id, user_id, name, ig_handle, instagram, bio, about)
    VALUES (v_org_id, auth.uid(), auth.uid(), COALESCE(NULLIF(trim(p_organizer_name), ''), 'Organizer'), p_instagram, p_instagram, p_about, p_about)
    RETURNING * INTO v_organizer;
  ELSE
    UPDATE organizers SET name = COALESCE(NULLIF(trim(p_organizer_name), ''), name), instagram = COALESCE(p_instagram, instagram), about = COALESCE(p_about, about) WHERE id = v_organizer.id;
  END IF;

  v_event_id := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr(md5(gen_random_uuid()::text), 1, 6);

  INSERT INTO events(id, key, slug, organizer_id, name, category, cat_key, cat_label, description, price_vnd, price_cents, capacity, seats_remaining, area, event_date, event_time, status, approval, visibility)
  VALUES (
    v_event_id,
    v_event_id,
    v_event_id,
    v_organizer.id,
    trim(p_name),
    p_category,
    p_category,
    p_category,
    COALESCE(p_description, ''),
    COALESCE(p_price_vnd, 0),
    COALESCE(p_price_vnd, 0) * 100,
    p_capacity,
    p_capacity,
    COALESCE(p_location, ''),
    p_event_date,
    p_event_time,
    'live',
    'host_approves',
    'public'
  )
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;
REVOKE EXECUTE ON FUNCTION create_event_draft FROM anon;
GRANT EXECUTE ON FUNCTION create_event_draft TO authenticated;
