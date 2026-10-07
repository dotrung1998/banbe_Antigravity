-- Make every demo-catalogue event messageable: (re)seed any missing demo rows.
--
-- The iOS/web catalogue (20 demo events, keys like 'bepnho') only has a chat
-- target if a matching `organizers` + `events` row exists in the database;
-- migration 020 seeded them but only for test accounts that existed at that
-- moment, so a DB can be missing some or all of them, and "Message host" then
-- has no organizer to create a conversation with. This re-seeds ONLY the missing
-- rows (ON CONFLICT DO NOTHING — existing rows are never touched), owned by the
-- test accounts (or, if none exist, whichever accounts do). Events that were
-- missing get upcoming dates so live ones aren't instantly "past". Test data only.

DO $$
DECLARE
  v_users uuid[];
  v_n int;
BEGIN
  SELECT array_agg(id) INTO v_users
  FROM auth.users
  WHERE lower(email) IN ('dotrung1998@gmail.com', 'doqanh0906@gmail.com', 'superdeutsche98@gmail.com');
  IF COALESCE(array_length(v_users, 1), 0) = 0 THEN
    SELECT array_agg(id) INTO v_users FROM (SELECT id FROM auth.users ORDER BY created_at LIMIT 3) u;
  END IF;
  v_n := COALESCE(array_length(v_users, 1), 0);
  IF v_n = 0 THEN
    RAISE NOTICE 'No accounts exist yet - skipping demo event re-seed.';
    RETURN;
  END IF;

  -- profiles.handle is NOT NULL (migration 079); same synthetic formula as 079/081/082.
  INSERT INTO public.profiles (id, display_name, phone, locale, role, handle)
  SELECT u.id, '', '', 'vi', 'participant', left('u' || replace(u.id::text, '-', ''), 13)
    FROM auth.users u WHERE u.id = ANY(v_users)
  ON CONFLICT (id) DO NOTHING;

  CREATE TEMP TABLE _demo_events (
    event_id text, org_name text, ig text, about text,
    cat_key text, cat_label text, category text, name text,
    description text, included text, area text, lat float8, lng float8,
    event_date date, event_time time, price_vnd int, seats int,
    status text, visibility text
  ) ON COMMIT DROP;

  INSERT INTO _demo_events VALUES
      ('bepnho', 'Bếp Nhỏ', '@bepnho.saigon', 'Minh nấu cho người lạ từ 2021, bắt đầu bằng vài cái bàn trong ga-ra. Mỗi tối một thực đơn, đi chợ Bà Chiểu lúc sáu giờ sáng.', 'supper', 'Supper club', 'Supper club', 'Bếp Nhỏ №12', 'Mười bốn chỗ. Một ga-ra cải tạo ở Bình Thạnh. Minh nấu món gì chợ sáng có.', '5 món ▪︎ rượu gạo ▪︎ cà phê', 'Bình Thạnh', 10.805524, 106.713668, '2026-07-11', '19:00', 900000, 3, 'live', 'public'),
      ('comnha', 'Cơm Nhà Mai', '@comnhamai', 'Mai dọn bữa tối trên sân thượng nhà mình, nấu kiểu cơm nhà miền Trung. Tám chỗ, không hơn.', 'supper', 'Supper club', 'Supper club', 'Cơm Nhà Mai', 'Tám chỗ quanh bếp than trên sân thượng. Mai nướng cá theo mùa.', '4 món ▪︎ trà ▪︎ tráng miệng', 'Quận 3', 10.780724, 106.691568, '2026-07-09', '19:30', 700000, 5, 'live', 'public'),
      ('bandai', 'Bàn Dài', '@bandai.supper', 'Một cái bàn dài, những người chưa từng gặp. Bàn Dài dọn bữa cho người lạ ngồi cạnh nhau từ 2022.', 'supper', 'Supper club', 'Supper club', 'Bàn Dài №4', 'Một bàn, mười sáu người lạ, sáu món. Không ai rời bàn trước món cuối.', '6 món ▪︎ rượu vang ▪︎ nước lọc đầy bình', 'Thảo Điền', 10.809288, 106.743716, '2026-07-10', '19:00', 1200000, 2, 'cancelled', 'public'),
      ('phokhuya', 'Phở Khuya', '@phokhuya', 'Tùng bán phở lúc nửa đêm cho người đi làm ca muộn và người không ngủ được. Mười hai ghế nhựa, một nồi nước.', 'supper', 'Supper club', 'Supper club', 'Phở Khuya', 'Phở lúc mười một giờ đêm, nước dùng hầm từ trưa. Mười hai ghế nhựa.', '1 tô ▪︎ quẩy ▪︎ trà đá', 'Quận 4', 10.758868, 106.700276, '2026-07-11', '23:00', 350000, 9, 'ended', 'public'),
      ('vuonsau', 'Vườn Sau', '@vuonsau.collective', 'Nhóm bạn nấu ăn trong khu vườn sau nhà ở Gò Vấp. Rau hái tại vườn, mưa thì dời vô hiên.', 'supper', 'Supper club', 'Supper club', 'Vườn Sau', 'Bữa tối trong vườn sau nhà, đèn dây và mưa thì dời vô hiên.', '5 món ▪︎ cocktail mở màn', 'Gò Vấp', 10.842428, 106.667996, '2026-07-12', '18:00', 850000, 6, 'live', 'public'),
      ('orbit', 'Rue Miche L''Édition', '@ruemiche', 'Cửa hàng và không gian sự kiện của các nhà thiết kế Việt. L''Édition là chuỗi buổi diễn giới thiệu bộ sưu tập mới, tổ chức tại xưởng.', 'fashion', 'Thời trang', 'Thời trang', 'ORBIT: Afterlight', 'Sàn thép, sân khấu tròn, khói. Bốn mươi phút, không nghỉ. Bộ sưu tập mới của L''Édition, lần đầu ra mắt ngoài cửa hàng.', 'Welcome drink ▪︎ zine L''Édition №4', 'Quận 1', 10.777344, 106.704008, '2026-07-10', '20:00', 400000, 23, 'live', 'public'),
      ('aeie', 'AEIE Studios', '@aeie.studios', 'Studio thời trang ở Thảo Điền, thành lập 2018. Tinh thần: bình thường hóa những điều khác thường.', 'fashion', 'Thời trang', 'Thời trang', 'AEIE: Mở Xưởng', 'Xưởng may mở cửa một buổi chiều. Xem rập, vải, và những mẫu chưa bao giờ bán.', 'Trà ▪︎ tour xưởng 30 phút', 'Thảo Điền', 10.799904, 106.738028, '2026-07-11', '16:00', 300000, 18, 'live', 'public'),
      ('fanci', 'Fanci Club', '@fanci.club', 'Thương hiệu của Duy Trần, cùng quỹ đạo sáng tạo với AEIE. Đồ may đo, thử tại chỗ.', 'fashion', 'Thời trang', 'Thời trang', 'Fanci: Đêm Thử Đồ', 'Thử đồ như một buổi tiệc. Gương, đèn, và một stylist mỗi ba khách.', 'Stylist ▪︎ đồ uống ▪︎ chỉnh sửa tại chỗ', 'Quận 1', 10.781640, 106.698080, '2026-07-09', '19:00', 500000, 0, 'live', 'public'),
      ('compound', 'Compound Garment', '@compound.garment', 'Streetwear địa phương, Quận 1. Drop giới hạn, thường bán trên sân thượng lúc chiều muộn.', 'fashion', 'Thời trang', 'Thời trang', 'Compound: Sân Thượng', 'Drop mới trên sân thượng, mặc thử dưới trời chiều. Bán hết là thôi.', 'Vào cửa ▪︎ sticker pack', 'Quận 1', 10.775532, 106.703324, '2026-07-12', '17:00', 250000, 31, 'live', 'public'),
      ('motlop', 'Mãi Mãi', '@maimai.mag', 'Tạp chí về chất liệu và nghề thủ công Việt. Mãi bám rễ nơi ta đến, mãi vươn về nơi ta tới.', 'fashion', 'Thời trang', 'Thời trang', 'Chỉ Một Lớp', 'Một đêm về vải: bốn nhà thiết kế, một chất liệu, bốn cách cắt.', 'Talk 40 phút ▪︎ đồ uống', 'Quận 3', 10.780556, 106.690392, '2026-07-08', '19:30', 600000, 8, 'ended', 'public'),
      ('vungtrang', 'Nguyen Art Foundation', '@nguyenartfoundation', 'Quỹ nghệ thuật đương đại tại HCMC, sưu tập và trưng bày nghệ sĩ Việt trong và ngoài nước.', 'gallery', 'Phòng tranh', 'Phòng tranh', 'Vùng Trắng', 'Sáu họa sĩ, một màu. Triển lãm nhóm về sự trống, mở cửa một đêm trước công chúng.', 'Catalogue ▪︎ trò chuyện với giám tuyển', 'Thảo Điền', 10.800192, 106.740044, '2026-07-12', '18:00', 150000, 41, 'live', 'public'),
      ('sonmai', 'Galerie Quỳnh', '@galeriequynh', 'Phòng tranh đương đại lâu đời của thành phố, chuyên nghệ sĩ Việt và quốc tế.', 'gallery', 'Phòng tranh', 'Phòng tranh', 'Đối Thoại Sơn Mài', 'Hai thế hệ sơn mài treo đối diện nhau. Người xem đứng giữa.', 'Vào cửa ▪︎ tài liệu triển lãm', 'Quận 1', 10.772760, 106.695920, '2026-07-10', '18:30', 100000, 26, 'live', 'public'),
      ('khongnguoi', 'Lâm', '@khongnguoi', 'Lâm chụp thành phố không người trong sáu năm, đi bộ lúc năm giờ sáng. Đây là triển lãm cá nhân đầu tiên.', 'gallery', 'Phòng tranh', 'Phòng tranh', 'Ảnh Không Người', 'Ba mươi tấm ảnh thành phố, không một bóng người. Chụp trong sáu năm.', 'Vào cửa ▪︎ print khổ nhỏ', 'Quận 3', 10.772936, 106.697052, '2026-07-11', '17:00', 120000, 35, 'live', 'public'),
      ('noigiay', 'Zone Publishing', '@zone.publishing', 'Nhà làm zine và sách nhỏ, tổ chức các buổi nói chuyện về nghề in và giấy.', 'gallery', 'Phòng tranh', 'Phòng tranh', 'Nói Chuyện: Giấy', 'Một giờ về giấy dó với người làm giấy đời thứ ba. Có mẫu để sờ.', 'Talk ▪︎ trà ▪︎ mẫu giấy mang về', 'Quận 1', 10.777704, 106.706528, '2026-07-08', '19:00', 80000, 20, 'live', 'public'),
      ('phong302', 'Phòng 302', '@phong302', 'Không gian nghệ thuật trong một căn hộ tập thể cũ ở Quận 5. Mỗi kỳ một nhóm nghệ sĩ.', 'gallery', 'Phòng tranh', 'Phòng tranh', 'Phòng 302', 'Triển lãm trong căn hộ tập thể cũ. Mỗi phòng một tác giả, giữ nguyên đồ đạc.', 'Vào cửa theo khung giờ', 'Quận 5', 10.757932, 106.662524, '2026-07-12', '15:00', 150000, 14, 'live', 'public'),
      ('chieucham', 'Yentown', '@yentown.saigon', 'Sân chơi phức hợp nghệ thuật ở Quận 1. Chiều Chậm là chuỗi buổi DJ thư giãn cuối tuần.', 'music', 'Nhạc', 'Nhạc', 'Chiều Chậm', 'Ba DJ, một buổi chiều, không danh sách nhạc định trước. Đến sớm có chỗ ngồi.', 'Vào cửa tự do ▪︎ cà phê tính riêng', 'Yentown, Quận 1', 10.771824, 106.701368, '2026-07-12', '15:00', 0, 58, 'live', 'public'),
      ('jazzgac', 'Gác', '@jazzogac', 'Gác gỗ hai mươi chỗ trên một con hẻm Quận 1. Jazz mộc, không micro, mỗi tuần một nhóm.', 'music', 'Nhạc', 'Nhạc', 'Jazz Ở Gác', 'Gác gỗ hai mươi chỗ, kèn không micro. Set hai bắt đầu lúc mười giờ.', '2 set ▪︎ một đồ uống', 'Quận 1', 10.778148, 106.697636, '2026-07-09', '21:00', 250000, 16, 'live', 'public'),
      ('bangcoi', 'Băng Cối', '@bangcoi.club', 'Câu lạc bộ nghe nhạc từ băng cối qua dàn loa cổ. Không điện thoại trong phòng nghe.', 'music', 'Nhạc', 'Nhạc', 'Băng Cối', 'Nghe nhạc từ băng cối qua dàn loa cũ. Không điện thoại trong phòng nghe.', 'Vào cửa ▪︎ trà nóng', 'Quận 3', 10.781120, 106.694340, '2026-07-10', '20:00', 180000, 22, 'live', 'public'),
      ('modular', 'OBJoff', '@objoff', 'Tập thể nhạc điện tử thử nghiệm với dàn máy modular. Không set nào lặp lại.', 'music', 'Nhạc', 'Nhạc', 'Đêm Modular', 'Bốn nghệ sĩ, bốn dàn máy, nối dây trực tiếp. Không có bài nào lặp lại.', 'Vào cửa ▪︎ earplugs miễn phí', 'Quận 4', 10.754908, 106.708556, '2026-07-11', '21:30', 200000, 27, 'live', 'public'),
      ('pianomuon', 'Nhà Piano', '@nhapiano', 'Một căn phòng, một cây đàn. Nhà Piano tổ chức recital muộn cho tối đa mười hai người.', 'music', 'Nhạc', 'Nhạc', 'Piano Muộn', 'Một cây đàn, một người chơi, đèn tắt gần hết. Bốn mươi lăm phút.', '1 set ▪︎ một ly vang', 'Quận 1', 10.781256, 106.695392, '2026-07-12', '22:00', 300000, 11, 'live', 'public');

  -- Only what is missing.
  DELETE FROM _demo_events d WHERE EXISTS (SELECT 1 FROM public.events e WHERE e.id = d.event_id);

  INSERT INTO public.organizers (id, owner_id, user_id, name, ig_handle, instagram, about, hosting_since)
  SELECT 'org_' || event_id, uid, uid, org_name, ig, ig, about, ''
  FROM (SELECT *, v_users[1 + floor(random() * v_n)::int] AS uid FROM _demo_events) assigned
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.events (
    id, organizer_id, slug, key, name, category, cat_key, cat_label,
    description, included, area, lat, lng, event_date, event_time,
    price_vnd, price_cents, capacity, seats_remaining, status, visibility, approval
  )
  SELECT
    event_id, 'org_' || event_id, event_id, event_id, name, category, cat_key, cat_label,
    description, included, area, lat, lng,
    CASE WHEN status = 'live' THEN current_date + 1 + (abs(hashtext(event_id)) % 20) ELSE event_date END,
    event_time,
    price_vnd, price_vnd::bigint * 100, GREATEST(seats, 1), seats,
    status::event_status, visibility::event_visibility, 'instant'
  FROM _demo_events
  ON CONFLICT (id) DO NOTHING;
END $$;

-- Opening messages for the rows just added (same five-variant scheme as 157;
-- only events still without a greeting are touched).
WITH pick AS (
  SELECT e.id,
         abs(hashtext(e.id::text)) % 5 AS k,
         coalesce(nullif(btrim(o.name), ''), 'host') AS nm
  FROM public.events e
  LEFT JOIN public.organizers o ON o.id = e.organizer_id
  WHERE (e.chat_greeting IS NULL OR btrim(e.chat_greeting) = '')
    AND (e.chat_greeting_en IS NULL OR btrim(e.chat_greeting_en) = '')
)
UPDATE public.events e
SET chat_greeting = left(CASE p.k
      WHEN 0 THEN 'Chào bạn, mình là ' || p.nm || '. Cứ nhắn mình thoải mái nhé!'
      WHEN 1 THEN 'Xin chào! Bạn có câu hỏi gì về sự kiện này không? Cứ hỏi nhé.'
      WHEN 2 THEN 'Cảm ơn bạn đã quan tâm đến sự kiện. Cần biết thêm gì, nhắn mình nhé!'
      WHEN 3 THEN 'Chào bạn! Mình sẵn sàng giải đáp mọi thắc mắc trước giờ diễn ra.'
      ELSE 'Hẹn gặp bạn ở sự kiện! Cần hỗ trợ gì cứ nhắn ở đây.' END, 500),
    chat_greeting_en = left(CASE p.k
      WHEN 0 THEN 'Hi, this is ' || p.nm || '. Feel free to message me anytime!'
      WHEN 1 THEN 'Hello! Got a question about this event? Just ask.'
      WHEN 2 THEN 'Thanks for your interest in the event. Message me if you need to know anything!'
      WHEN 3 THEN 'Hi there! Happy to answer any questions before the event.'
      ELSE 'Looking forward to seeing you! Message here if you need anything.' END, 500)
FROM pick p
WHERE e.id = p.id;
