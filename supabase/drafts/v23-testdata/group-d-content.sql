-- v2.3 test data, group D: content fill on the 21 live test events (generated from group-d-content.json).
-- Writes description, intro (date-free), included_items details, and merges type facts into details.
-- Also Gác (org_jazzgac) organizers.about. NOT a migration. Ends in ROLLBACK (dry run).
-- Rollback: supabase/rollbacks/v23_testdata_group_d_rollback.sql (exact old values).
BEGIN;
CREATE TEMP TABLE v23_d_before ON COMMIT DROP AS
SELECT key, description, intro, included_items, details FROM events WHERE key IN ('aeie-2','compound','fanci','motlop','orbit','khongnguoi','noigiay','phong302','sonmai-2','vungtrang','bangcoi','chieucham','jazzgac','modular','pianomuon','bandai','banrieng','bepnho','comnha','phokhuya','vuonsau');
DO $$ BEGIN
  IF (SELECT count(*) FROM v23_d_before) <> 21 THEN RAISE EXCEPTION 'key mismatch'; END IF;
  IF EXISTS (SELECT 1 FROM events WHERE key IN (SELECT key FROM v23_d_before) AND status <> 'live') THEN RAISE EXCEPTION 'not all live'; END IF;
END $$;
UPDATE events SET description=$v23$Xưởng may của AEIE mở cửa một buổi chiều cho người ngoài. Bạn đi qua bàn cắt, xem rập giấy treo thành hàng, sờ những cuộn vải đang chờ thành áo. Cuối buổi là một góc nhỏ với những mẫu thử chưa bao giờ được bán, mặc thử thoải mái. Nhóm nhỏ, đi theo người thợ cả, hỏi gì cũng được.$v23$, intro=$v23$AEIE mở xưởng may ở Thảo Điền cho một nhóm nhỏ, vào một buổi chiều.

Đi theo người thợ cả qua bàn cắt và kho vải, rồi dừng lại ở góc mẫu thử. Có trà, không có quầy bán hàng.$v23$, included_items=$v23$[{"detail":"trà sen nóng, rót suốt buổi","label":"Trà"},{"detail":"đi cùng thợ cả, nhóm tối đa sáu người","label":"tour xưởng 30 phút"}]$v23$::jsonb WHERE key='aeie-2';
UPDATE events SET description=$v23$Compound ra drop mới trên sân thượng một toà nhà cũ ở Quận 1. Hàng treo trên giá sắt, phòng thử là tấm rèm căng giữa hai cột, gương dựng vào lan can. Mặc thử dưới trời chiều, mua bằng tiền mặt hoặc chuyển khoản. Bán hết là thôi, không giữ hàng, không ship sau.$v23$, intro=$v23$Drop mới của Compound, bán ngay trên sân thượng.

Mặc thử dưới trời chiều, mua tại chỗ. Bán hết là đóng cửa.$v23$, included_items=$v23$[{"detail":"vào và ra tự do trong khung giờ","label":"Vào cửa"},{"detail":"bộ sticker của drop này","label":"sticker pack"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Bia lạnh bán tại quầy"}$v23$::jsonb WHERE key='compound';
UPDATE events SET description=$v23$Fanci biến buổi thử đồ thành một bữa tiệc nhỏ. Phòng có gương lớn, đèn ấm và một stylist đi cùng bạn từ lúc bước vào. Thử bao nhiêu bộ cũng được, thợ chỉnh sửa ngồi ngay tại chỗ nếu bạn muốn mang về luôn. Đồ uống mời suốt buổi. Hẹn giờ trước để stylist chuẩn bị sẵn vài bộ hợp dáng bạn.$v23$, intro=$v23$Một đêm thử đồ có stylist riêng, đồ uống và thợ chỉnh sửa ngồi ngay bên cạnh.

Đến tay không, về với một bộ vừa người.$v23$, included_items=$v23$[{"detail":"một stylist đi cùng bạn cả buổi","label":"Stylist"},{"detail":"vang trắng hoặc nước chanh sả","label":"đồ uống"},{"detail":"lên lai, bóp eo, xong trong 20 phút","label":"chỉnh sửa tại chỗ"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Vang trắng mời trong buổi"}$v23$::jsonb WHERE key='fanci';
UPDATE events SET description=$v23$Một đêm chỉ nói về vải. Bốn nhà thiết kế nhận cùng một chất liệu, một tấm lanh mộc dệt tay, và mỗi người cắt theo một cách. Họ kể vì sao chọn đường cắt đó, cái gì hỏng, cái gì giữ lại. Bốn bộ đồ treo giữa phòng để bạn lật xem từng đường may. Cuối buổi có thể đặt may lại bất kỳ bộ nào.$v23$, intro=$v23$Bốn nhà thiết kế, cùng một tấm vải, bốn cách cắt.

Một buổi talk nhỏ về chất liệu, có đồ thật để cầm lên xem.$v23$, included_items=$v23$[{"detail":"bốn nhà thiết kế, mỗi người mười phút","label":"Talk 40 phút"},{"detail":"một ly bất kỳ ở quầy","label":"đồ uống"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Quầy có bia và vang, tính riêng"}$v23$::jsonb WHERE key='motlop';
UPDATE events SET description=$v23$Sàn thép, sân khấu tròn, khói mỏng. Bốn mươi phút trình diễn liền mạch, không nghỉ, không MC. Đây là lần đầu bộ sưu tập Afterlight của L'Édition rời khỏi cửa hàng. Sau show, các mẫu đồ được treo lại để bạn xem gần, và nhà thiết kế ở lại trò chuyện. Đến sớm để có chỗ đứng sát sàn.$v23$, intro=$v23$ORBIT là show đầu tiên của bộ sưu tập Afterlight bên ngoài cửa hàng L'Édition.

Bốn mươi phút không nghỉ, rồi đồ được treo lại để xem gần.$v23$, included_items=$v23$[{"detail":"một ly khi vào cửa","label":"Welcome drink"},{"detail":"bản in giới hạn, mang về","label":"zine L'Édition №4"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Một ly chào mừng khi vào cửa"}$v23$::jsonb WHERE key='orbit';
UPDATE events SET description=$v23$Ba mươi tấm ảnh thành phố không một bóng người, chụp trong sáu năm, phần lớn vào lúc năm giờ sáng hoặc ngày mùng một Tết. Trần Vũ đi bộ với một máy phim và chờ đến khi con đường trống hẳn. Triển lãm treo theo giờ chụp, từ sáng sớm tới khuya. Tác giả có mặt cả buổi để kể về từng tấm.$v23$, intro=$v23$Ba mươi tấm ảnh Sài Gòn khi không có ai.

Trần Vũ chụp trong sáu năm, phần lớn lúc trời chưa sáng. Ảnh treo theo giờ chụp.$v23$, included_items=$v23$[{"detail":"xem không giới hạn thời gian","label":"Vào cửa"},{"detail":"một tấm in A6 chọn trong năm mẫu","label":"print khổ nhỏ"}]$v23$::jsonb WHERE key='khongnguoi';
UPDATE events SET description=$v23$Một giờ ngồi cùng người làm giấy dó đời thứ ba của Xưởng Giấy Dó. Anh kể về cây dó, về nồi nấu vỏ, về tấm liềm xeo giấy, và vì sao giấy này sống được vài trăm năm. Có mẫu để sờ, có tấm đang phơi dở để xem gần. Mỗi người mang về một xấp nhỏ. Phù hợp cả cho người chưa từng cầm giấy dó.$v23$, intro=$v23$Một buổi trò chuyện về giấy dó với người làm giấy đời thứ ba.

Có mẫu để sờ và một xấp giấy mang về.$v23$, included_items=$v23$[{"detail":"khoảng 60 phút, hỏi đáp cuối buổi","label":"Talk"},{"detail":"trà nóng suốt buổi","label":"trà"},{"detail":"một xấp năm tờ khổ A5","label":"mẫu giấy mang về"}]$v23$::jsonb WHERE key='noigiay';
UPDATE events SET description=$v23$Triển lãm diễn ra trong một căn hộ tập thể cũ ở Quận 5. Mỗi phòng thuộc về một tác giả, đồ đạc của chủ nhà được giữ nguyên, tranh treo giữa tủ thờ và kệ sách. Lê Na, Đỗ Khang và Hà My làm việc với sơn dầu, sơn mài, tranh in và sắp đặt. Vào theo khung giờ để căn hộ không quá đông.$v23$, intro=$v23$Ba tác giả, ba căn phòng trong một căn hộ tập thể cũ, đồ đạc giữ nguyên.

Vào theo khung giờ, mỗi lượt một nhóm nhỏ.$v23$, included_items=$v23$[{"detail":"mỗi lượt 45 phút, chọn khung khi giữ chỗ","label":"Vào cửa theo khung giờ"}]$v23$::jsonb WHERE key='phong302';
UPDATE events SET description=$v23$Hai thế hệ sơn mài treo đối diện nhau trong cùng một phòng. Một bên là tranh của Nguyễn Tư từ những năm tám mươi, bên kia là tác phẩm mới của con gái ông, Nguyễn Tư An. Người xem đứng ở giữa và tự thấy chỗ hai người giống nhau, chỗ họ cãi nhau. Giám tuyển có mặt từ sáu giờ rưỡi.$v23$, intro=$v23$Cha và con gái, hai thế hệ sơn mài, treo đối diện nhau.

Đứng ở giữa và tự xem cuộc đối thoại.$v23$, included_items=$v23$[{"detail":"xem không giới hạn thời gian","label":"Vào cửa"},{"detail":"sách mỏng song ngữ về từng tác phẩm","label":"tài liệu triển lãm"}]$v23$::jsonb WHERE key='sonmai-2';
UPDATE events SET description=$v23$Sáu họa sĩ cùng làm việc với một màu trắng. Phạm Thu, Lý Đan, Ngô Bảo và ba người bạn treo tranh và sắp đặt về sự trống, về những gì còn lại khi bỏ bớt. Triển lãm mở cửa một đêm cho công chúng trước khi chuyển về kho của quỹ. Giám tuyển dẫn hai vòng xem lúc bảy giờ và tám giờ.$v23$, intro=$v23$Sáu họa sĩ, một màu trắng, một đêm mở cửa.

Giám tuyển dẫn hai vòng xem, catalogue mang về.$v23$, included_items=$v23$[{"detail":"bản in 40 trang","label":"Catalogue"},{"detail":"hai vòng xem, lúc 19:00 và 20:00","label":"trò chuyện với giám tuyển"}]$v23$::jsonb WHERE key='vungtrang';
UPDATE events SET description=$v23$Phòng nghe nhỏ ở Quận 3, ghế xếp quanh một dàn loa cũ và một đầu băng cối. Mỗi tối chủ nhà chọn hai cuộn băng, nhạc folk và indie Việt thập niên chín mươi, và kể chuyện từng cuộn. Không điện thoại trong phòng nghe, có hộp gửi ở cửa. Trà nóng rót suốt buổi.$v23$, intro=$v23$Nghe băng cối qua dàn loa cũ, trong một căn phòng không có điện thoại.

Hai cuộn băng, một ấm trà, và câu chuyện của người sưu tầm.$v23$, included_items=$v23$[{"detail":"một chỗ ngồi trong phòng nghe","label":"Vào cửa"},{"detail":"trà mạn rót suốt buổi","label":"trà nóng"}]$v23$::jsonb WHERE key='bangcoi';
UPDATE events SET description=$v23$Buổi chiều nghe nhạc mộc ở Yentown, không danh sách bài định trước. Mây Chiều hát, Tú đệm guitar, và họ chơi theo những gì khán giả đang ngồi đó muốn nghe. Đến sớm có ghế, đến muộn ngồi bậc thang. Cà phê và nước ép tính riêng ở quầy, vào cửa tự do. Mang theo một bài bạn muốn nghe, họ có thể chơi.$v23$, intro=$v23$Một buổi chiều nhạc mộc, không danh sách bài, vào cửa tự do.

Đến sớm có ghế, đến muộn ngồi bậc thang.$v23$, included_items=$v23$[{"detail":"không cần vé giấy, giữ chỗ để có ghế","label":"Vào cửa tự do"},{"detail":"quầy mở suốt buổi","label":"cà phê tính riêng"}]$v23$::jsonb WHERE key='chieucham';
UPDATE events SET description=$v23$Căn gác gỗ ở Quận 1, khoảng hai mươi chỗ ngồi sát sân khấu. Bộ ba Gác chơi không micro, kèn và contrabass đủ lấp căn phòng. Set một từ chín giờ, set hai từ mười giờ với khách mời Linh Sax. Một đồ uống đã gồm trong vé, quầy mở tới khi tắt đèn. Cầu thang dốc, nên đi giày đế bằng.$v23$, intro=$v23$Jazz không micro trên một căn gác gỗ ở Quận 1.

Hai set, một khách mời, một đồ uống đã gồm trong vé.$v23$, included_items=$v23$[{"detail":"21:00 và 22:00, mỗi set khoảng 45 phút","label":"2 set"},{"detail":"bia, vang hoặc nước không cồn","label":"một đồ uống"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Một đồ uống gồm trong vé, quầy tính riêng sau đó"}$v23$::jsonb WHERE key='jazzgac';
UPDATE events SET description=$v23$Bốn nghệ sĩ, bốn dàn synth modular, nối dây trực tiếp trước mặt khán giả. Không có bài thu sẵn, mỗi âm thanh được tạo ra ngay lúc đó và không lặp lại. Phòng đứng, đèn thấp, loa lớn. Có earplugs ở cửa, quầy bia mở cả đêm. Mở cửa trước nửa giờ để bạn xem các dàn máy khi chưa bật tiếng.$v23$, intro=$v23$Một đêm synth modular, nối dây trực tiếp, không bài nào lặp lại.

Phòng đứng, loa lớn, earplugs ở cửa.$v23$, included_items=$v23$[{"detail":"vào và ra tự do","label":"Vào cửa"},{"detail":"lấy ở bàn soát vé","label":"earplugs miễn phí"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Bia và cocktail bán tại quầy"}$v23$::jsonb WHERE key='modular';
UPDATE events SET description=$v23$Một cây đàn upright, một người chơi, đèn tắt gần hết. Minh Châu chơi bốn mươi lăm phút Chopin và Satie, không giới thiệu giữa các bài. Khán giả ngồi trên sofa và nệm quanh đàn. Một ly vang đỏ đã gồm trong vé, rót khi bạn đến. Đến trước mười phút, cửa đóng khi bắt đầu chơi.$v23$, intro=$v23$Bốn mươi lăm phút piano trong căn phòng gần như tối.

Một người chơi, một ly vang, không ai nói chuyện giữa các bài.$v23$, included_items=$v23$[{"detail":"khoảng 45 phút, không nghỉ","label":"1 set"},{"detail":"vang đỏ rót khi vào","label":"một ly vang"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Một ly vang đỏ gồm trong vé"}$v23$::jsonb WHERE key='pianomuon';
UPDATE events SET description=$v23$Một chiếc bàn dài ở Thảo Điền cho những người chưa từng gặp nhau. Sáu món đi theo mùa, rượu vang rót theo món, nước lọc luôn đầy bình. Không ai rời bàn trước món cuối, và thường là ngồi thêm một lúc nữa. Báo trước nếu bạn kiêng món gì, bếp sẽ đổi cho bạn.$v23$, intro=$v23$Một chiếc bàn dài, sáu món, và những người lạ ngồi cạnh nhau.

Rượu rót theo món, không ai rời bàn trước món cuối.$v23$, included_items=$v23$[{"detail":"thực đơn theo mùa, báo trước nếu kiêng","label":"6 món"},{"detail":"rót theo từng món","label":"rượu vang"},{"detail":"luôn có trên bàn","label":"nước lọc đầy bình"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Vang rót theo món, có lựa chọn không cồn","dietary_note":"Báo trước 24 giờ để bếp đổi món"}$v23$::jsonb WHERE key='bandai';
UPDATE events SET description=$v23$Bàn Riêng không đăng công khai. Minh nấu cho vài người quen của người quen trong căn bếp ở Bình Thạnh, bảy món dựa trên những gì chợ sáng có, hải sản là chính. Rượu vang chọn riêng cho từng món. Ăn mặc lịch sự, đến đúng giờ vì món đầu ra ngay khi đủ người.$v23$, intro=$v23$Một bàn ăn riêng, chỉ dành cho người được mời.

Bảy món theo chợ sáng, rượu vang chọn riêng cho từng món.$v23$, included_items=$v23$[{"detail":"hải sản là chính, đổi được nếu kiêng","label":"7 món"},{"detail":"một ly cho mỗi món","label":"rượu vang chọn riêng"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Vang chọn riêng theo món","dietary_note":"Có thực đơn không thịt, báo trước khi giữ chỗ"}$v23$::jsonb WHERE key='banrieng';
UPDATE events SET description=$v23$Một ga-ra cải tạo ở Bình Thạnh, một chiếc bàn dài. Minh nấu những gì chợ Bà Chiểu có vào sáng hôm đó, nên thực đơn không lặp lại và không ai biết trước. Năm món, rượu gạo rót tới khi hết chuyện, cà phê phin để kết thúc. Người lạ ngồi cạnh nhau, ra về thường là bạn.$v23$, intro=$v23$Bữa tối trong một ga-ra ở Bình Thạnh, thực đơn theo chợ sáng.

Năm món, rượu gạo, và người lạ ngồi cạnh nhau.$v23$, included_items=$v23$[{"detail":"theo chợ Bà Chiểu sáng hôm đó","label":"5 món"},{"detail":"rót tới khi hết chuyện","label":"rượu gạo"},{"detail":"cà phê phin cuối bữa","label":"cà phê"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Rượu gạo gồm trong vé","dietary_note":"Có bản chay cho từng món"}$v23$::jsonb WHERE key='bepnho';
UPDATE events SET description=$v23$Bữa cơm quanh bếp than trên sân thượng ở Quận 3. Mai nướng cá theo mùa, nấu canh chua, rau hái từ chậu trên sân. Bốn món ăn chung theo kiểu cơm nhà, trà nóng và một món tráng miệng. Không có rượu, mặc thoải mái, mang theo câu chuyện. Bàn nhỏ, nên mọi người thường nói chuyện tới khuya.$v23$, intro=$v23$Cơm nhà quanh bếp than trên sân thượng.

Cá nướng theo mùa, canh chua, rau hái tại chỗ.$v23$, included_items=$v23$[{"detail":"ăn chung kiểu cơm nhà","label":"4 món"},{"detail":"trà nóng suốt bữa","label":"trà"},{"detail":"chè hoặc trái cây theo mùa","label":"tráng miệng"}]$v23$::jsonb, details=details || $v23${"dietary_note":"Có bản chay, báo khi giữ chỗ"}$v23$::jsonb WHERE key='comnha';
UPDATE events SET description=$v23$Phở lúc mười một giờ đêm ở một góc hẻm Quận 4. Tùng hầm nước dùng từ trưa, xương bò và quế hồi rang trên lửa than. Mười hai ghế nhựa, một tô, quẩy giòn và trà đá. Dành cho người đi làm ca muộn, người không ngủ được, và người chỉ muốn một tô phở thật nóng.$v23$, intro=$v23$Một tô phở lúc nửa đêm, nước dùng hầm từ trưa.

Ghế nhựa, quẩy giòn, trà đá.$v23$, included_items=$v23$[{"detail":"tái, chín hoặc nạm","label":"1 tô"},{"detail":"chiên ngay khi bạn ngồi","label":"quẩy"},{"detail":"rót thêm thoải mái","label":"trà đá"}]$v23$::jsonb, details=details || $v23${"dietary_note":"Nói trước nếu cần bỏ hành hoặc rau thơm"}$v23$::jsonb WHERE key='phokhuya';
UPDATE events SET description=$v23$Bữa tối trong khu vườn sau nhà ở Gò Vấp, đèn dây treo giữa hai cây xoài. Năm món dùng rau hái tại vườn, có bản chay và không gluten. Cocktail mở màn pha từ trái cây trong vườn. Nếu trời mưa, cả bàn dời vào hiên và bữa tối vẫn tiếp tục. Có muỗi vào mùa mưa, chủ nhà để sẵn tinh dầu sả.$v23$, intro=$v23$Bữa tối giữa vườn, rau hái tại chỗ, đèn dây trên đầu.

Mưa thì dời vào hiên, bữa tối vẫn tiếp tục.$v23$, included_items=$v23$[{"detail":"rau hái tại vườn, có bản chay","label":"5 món"},{"detail":"pha từ trái cây trong vườn","label":"cocktail mở màn"}]$v23$::jsonb, details=details || $v23${"alcohol_note":"Cocktail mở màn, có bản không cồn","dietary_note":"Có bản chay và không gluten"}$v23$::jsonb WHERE key='vuonsau';
UPDATE organizers SET about=$v23$Căn gác gỗ trên một toà nhà cũ ở Quận 1, mở cửa cho jazz không micro vào cuối tuần. Bộ ba Gác chơi thường xuyên và mời một khách mời mỗi đêm.$v23$ WHERE id='org_jazzgac' AND name='Gác';
SELECT b.key, length(b.description)||' → '||length(e.description) AS about_len,
       left(replace(b.intro,E'\n',' '),48)||' → '||left(replace(e.intro,E'\n',' '),48) AS intro,
       (SELECT count(*) FROM jsonb_array_elements(e.included_items) x WHERE x->>'detail' <> '') AS items_with_detail,
       (SELECT string_agg(k, ',') FROM jsonb_object_keys(e.details) k WHERE NOT b.details ? k) AS facts_added,
       e.intro ~ 'tháng|Thứ|Chủ nhật' AS intro_has_date,
       (SELECT length(about) FROM organizers WHERE id='org_jazzgac') AS gac_about_len
  FROM v23_d_before b JOIN events e USING (key) ORDER BY b.key;
ROLLBACK;
