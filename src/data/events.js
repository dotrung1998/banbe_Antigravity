// Event catalogue ported from the Góc design prototype (Goc Standalone Src.dc.html).
// Deterministic, in-memory "database" — swap for a real API later behind the same shape.

// User-provided photos (app/public/photos). Cycled across events/galleries —
// there are fewer real photos than events, so several events share a photo.
// Ordered color-first (by measured HSL saturation), then black-and-white,
// so events/hero images preferentially land on color photos.
const LOCAL_PHOTOS = [
  'DSCF4423.jpg', 'DSCF5481.jpg', 'DSCF6107.jpg', 'DSCF5891.jpg', 'DSCF2836.jpg',
  'DSCF4627.jpg', 'DSCF2503.jpg', 'DSCF4254.jpg', 'DSCF5796.jpg', 'DSCF5780.jpg',
  'DSCF2539.jpg', 'DSCF4517.jpg', 'DSCF6366.jpg', 'DSCF4223.jpg', 'DSCF5542.jpg',
  'DSCF2341.jpg', 'DSCF4238.jpg', 'DSCF7257.jpg', 'DSCF6279.jpg', 'DSCF4282.jpg',
  'DSCF4550.jpg', 'DSCF4212.jpg', 'DSCF4880.jpg', 'DSCF4488.jpg', 'DSCF4889.jpg',
  'DSCF7202.jpg', 'DSCF7039.jpg', 'DSCF6022.jpg', 'DSCF4207.jpg', 'DSCF6837.jpg',
  'DSCF2438.jpg', 'DSCF4864.jpg', 'DSCF4196.jpg', 'DSCF6368.jpg', 'DSCF2237.jpg',
  'DSCF5973.jpg', 'DSCF4058.jpg', 'DSCF4039.jpg', 'DSCF4065.jpg',
  // black-and-white (measured zero saturation) — kept, but ordered last
  'DSCF7752.jpg', 'DSCF7609.jpg', 'DSCF7597.jpg', 'DSCF7584.jpg', 'DSCF7576.jpg',
  'DSCF7556.jpg', 'DSCF7501.jpg', 'DSCF7459.jpg', 'DSCF5586.jpg', 'DSCF2128.jpg',
  'DSCF2101.jpg', 'DSCF2095.jpg', 'DSCF2060.jpg', 'DSCF2023.jpg', 'DSCF1740.jpg',
  'DSCF1683.jpg',
];

// One paper, one ink — event/organizer screens no longer tint by palette; the
// key is kept on each event only so the data shape (and create-screen picker)
// stays meaningful.
const FLAT = { bg: '#F7F4EC', text: '#1B1916', accent: '#1B1916', btnText: '#F7F4EC', muted: '#1B1916', metaC: '#1B1916', body: '#1B1916', rule: 'rgba(27,25,22,0.16)' };
const PALETTES = { ember: FLAT, slate: FLAT, studio: FLAT };

// key, catKey, cat, name, imgId, area, km, dayShort, dayLong, time, price, seatsN, desc, included, host, hostShort, pal, greeting
const ROWS = [
  ['bepnho','supper','Supper club','Bếp Nhỏ №12','1k2OUQ4phaA_Wo5q8o63pF0gZwmVH5QYt','Bình Thạnh','2,1','Th 7, 11.07','Thứ Bảy, 11 tháng 7','19:00','900.000₫',3,'Mười bốn chỗ. Một ga-ra cải tạo ở Bình Thạnh. Minh nấu món gì chợ sáng có.','5 món ▪︎ rượu gạo ▪︎ cà phê','Minh, @bepnho.saigon','Minh','ember','Chào bạn, mình là Minh. Cứ hỏi thoải mái nhé.'],
  ['comnha','supper','Supper club','Cơm Nhà Mai','1Gzi7se3lSLR31gIaXLN1JS38beue3dru','Quận 3','3,4','Th 5, 09.07','Thứ Năm, 9 tháng 7','19:30','700.000₫',5,'Tám chỗ quanh bếp than trên sân thượng. Mai nướng cá theo mùa.','4 món ▪︎ trà ▪︎ tráng miệng','Mai, @comnhamai','Mai','ember','Mai đây. Nhà có cầu thang hơi dốc, báo trước nếu cần hỗ trợ nhé.'],
  ['bandai','supper','Supper club','Bàn Dài №4','1sPaSlc3VOIQLYicg6xXnRTNP8uZ6CHUR','Thảo Điền','6,1','Th 6, 10.07','Thứ Sáu, 10 tháng 7','19:00','1.200.000₫',2,'Một bàn, mười sáu người lạ, sáu món. Không ai rời bàn trước món cuối.','6 món ▪︎ rượu vang ▪︎ nước lọc đầy bình','Bàn Dài','Bàn Dài','ember','Bàn Dài xin chào. Ăn chay hay dị ứng gì cứ nhắn.'],
  ['phokhuya','supper','Supper club','Phở Khuya','1y7GltUm7EqzQgMpguVNZwsAqJ6Sn42sN','Quận 4','2,8','Th 7, 11.07','Thứ Bảy, 11 tháng 7','23:00','350.000₫',9,'Phở lúc mười một giờ đêm, nước dùng hầm từ trưa. Mười hai ghế nhựa.','1 tô ▪︎ quẩy ▪︎ trà đá','Tùng, @phokhuya','Tùng','ember','Tùng đây. Đến trễ 15 phút là hết nước béo nha.'],
  ['vuonsau','supper','Supper club','Vườn Sau','1RlBmTVVqxoekYWNjc81XT2__ALPRI1zK','Gò Vấp','7,2','CN, 12.07','Chủ Nhật, 12 tháng 7','18:00','850.000₫',6,'Bữa tối trong vườn sau nhà, đèn dây và mưa thì dời vô hiên.','5 món ▪︎ cocktail mở màn','Vườn Sau','Vườn Sau','ember','Vườn Sau chào bạn. Tối có muỗi, mình có xịt sẵn.'],

  ['orbit','fashion','Thời trang','ORBIT: Afterlight','1cbiDLyQ543HL0fIsC98PfgIxdpfLT0DP','Quận 1','4,8','Th 6, 10.07','Thứ Sáu, 10 tháng 7','20:00','400.000₫',23,'Sàn thép, sân khấu tròn, khói. Bốn mươi phút, không nghỉ. Bộ sưu tập mới của L\'Édition, lần đầu ra mắt ngoài cửa hàng.','Welcome drink ▪︎ zine L\'Édition №4','Rue Miche L\'Édition','Rue Miche','slate','Rue Miche đây. Có gì cần hỏi về buổi diễn không?'],
  ['aeie','fashion','Thời trang','AEIE: Mở Xưởng','185dkcSxoO82-bSqps4NkXmUQrcdWRHpg','Thảo Điền','6,3','Th 7, 11.07','Thứ Bảy, 11 tháng 7','16:00','300.000₫',18,'Xưởng may mở cửa một buổi chiều. Xem rập, vải, và những mẫu chưa bao giờ bán.','Trà ▪︎ tour xưởng 30 phút','AEIE Studios','AEIE','slate','AEIE đây, hỏi gì cứ nhắn.'],
  ['fanci','fashion','Thời trang','Fanci: Đêm Thử Đồ','1ybcnaPSnegVfyp8vZat1Ja3aG5hXi5On','Quận 1','5,0','Th 5, 09.07','Thứ Năm, 9 tháng 7','19:00','500.000₫',12,'Thử đồ như một buổi tiệc. Gương, đèn, và một stylist mỗi ba khách.','Stylist ▪︎ đồ uống ▪︎ chỉnh sửa tại chỗ','Fanci Club','Fanci','slate','Fanci nghe. Size ngoài bảng cứ hỏi, xưởng may được.'],
  ['compound','fashion','Thời trang','Compound: Sân Thượng','1Li1u39LI2YuFEjgGsXpra6PpnDIZvPUX','Quận 1','4,6','CN, 12.07','Chủ Nhật, 12 tháng 7','17:00','250.000₫',31,'Drop mới trên sân thượng, mặc thử dưới trời chiều. Bán hết là thôi.','Vào cửa ▪︎ sticker pack','Compound Garment','Compound','slate','Compound đây. Drop giới hạn, mỗi người hai món thôi nha.'],
  ['motlop','fashion','Thời trang','Chỉ Một Lớp','1SM6A2Bc98_0_ZsUL-fEh1u4D3oHq6Gt4','Quận 3','3,9','Th 4, 08.07','Thứ Tư, 8 tháng 7','19:30','600.000₫',8,'Một đêm về vải: bốn nhà thiết kế, một chất liệu, bốn cách cắt.','Talk 40 phút ▪︎ đồ uống','Mãi Mãi × banbe','Mãi Mãi','slate','Mãi Mãi đây. Buổi này nói tiếng Việt, có phụ đề Anh.'],

  ['vungtrang','gallery','Phòng tranh','Vùng Trắng','1WCaK77T-85Vz8BOSS1NT4bfMC0ZDAwfS','Thảo Điền','6,3','CN, 12.07','Chủ Nhật, 12 tháng 7','18:00','150.000₫',41,'Sáu họa sĩ, một màu. Triển lãm nhóm về sự trống, mở cửa một đêm trước công chúng.','Catalogue ▪︎ trò chuyện với giám tuyển','Nguyen Art Foundation','NAF','studio','Xin chào. Đây là kênh của Nguyen Art Foundation.'],
  ['sonmai','gallery','Phòng tranh','Đối Thoại Sơn Mài','1kxxaSQMUKkf89LnSe4HwGcvimXub8sX7','Quận 1','4,4','Th 6, 10.07','Thứ Sáu, 10 tháng 7','18:30','100.000₫',26,'Hai thế hệ sơn mài treo đối diện nhau. Người xem đứng giữa.','Vào cửa ▪︎ tài liệu triển lãm','Galerie Quỳnh','Quỳnh','studio','Chào bạn, Galerie Quỳnh đây.'],
  ['khongnguoi','gallery','Phòng tranh','Ảnh Không Người','1bZUIyFGakgKSN3qBuN-AwZqpiU_wFJZm','Quận 3','3,2','Th 7, 11.07','Thứ Bảy, 11 tháng 7','17:00','120.000₫',35,'Ba mươi tấm ảnh thành phố, không một bóng người. Chụp trong sáu năm.','Vào cửa ▪︎ print khổ nhỏ','Lâm, @khongnguoi','Lâm','studio','Lâm đây. Ảnh không bán tại chỗ, chỉ đặt trước.'],
  ['noigiay','gallery','Phòng tranh','Nói Chuyện: Giấy','1FSTutTTmGnMgrRSOrFvdrsMaQ7ON7y6B','Quận 1','4,9','Th 4, 08.07','Thứ Tư, 8 tháng 7','19:00','80.000₫',20,'Một giờ về giấy dó với người làm giấy đời thứ ba. Có mẫu để sờ.','Talk ▪︎ trà ▪︎ mẫu giấy mang về','Zone Publishing','Zone','studio','Zone đây. Buổi talk có ghi hình, ngồi hàng sau nếu ngại.'],
  ['phong302','gallery','Phòng tranh','Phòng 302','1koPFwcKRxI9VlbBZCJSdwLW_xya9YJU5','Quận 5','5,7','CN, 12.07','Chủ Nhật, 12 tháng 7','15:00','150.000₫',14,'Triển lãm trong căn hộ tập thể cũ. Mỗi phòng một tác giả, giữ nguyên đồ đạc.','Vào cửa theo khung giờ','Phòng 302','302','studio','302 đây. Lên cầu thang bộ, tầng ba, cửa xanh.'],

  ['chieucham','music','Nhạc','Chiều Chậm','1OunhYV4NfYgBVgbkKXivFrhnCI711C2c','Yentown, Quận 1','4,5','CN, 12.07','Chủ Nhật, 12 tháng 7','15:00','Miễn phí',58,'Ba DJ, một buổi chiều, không danh sách nhạc định trước. Đến sớm có chỗ ngồi.','Vào cửa tự do ▪︎ cà phê tính riêng','Yentown','Yentown','slate','Yentown nghe đây.'],
  ['jazzgac','music','Nhạc','Jazz Ở Gác','1TJ9VkUPgsDILi7K1gEPk93z_Txtw1tVP','Quận 1','4,7','Th 5, 09.07','Thứ Năm, 9 tháng 7','21:00','250.000₫',16,'Gác gỗ hai mươi chỗ, kèn không micro. Set hai bắt đầu lúc mười giờ.','2 set ▪︎ một đồ uống','Gác, @jazzogac','Gác','slate','Gác đây. Set hai đông hơn, thích yên thì đến set một.'],
  ['bangcoi','music','Nhạc','Băng Cối','1mW5YR-nCRRNhP0AVkzTzLcTTVKgJZorn','Quận 3','3,6','Th 6, 10.07','Thứ Sáu, 10 tháng 7','20:00','180.000₫',22,'Nghe nhạc từ băng cối qua dàn loa cũ. Không điện thoại trong phòng nghe.','Vào cửa ▪︎ trà nóng','Băng Cối','Băng Cối','slate','Băng Cối đây. Phòng nghe im lặng tuyệt đối nha.'],
  ['modular','music','Nhạc','Đêm Modular','1Xv5FpSs4sW2wbYuxC0pVpIkgOK18acNU','Quận 4','3,0','Th 7, 11.07','Thứ Bảy, 11 tháng 7','21:30','200.000₫',27,'Bốn nghệ sĩ, bốn dàn máy, nối dây trực tiếp. Không có bài nào lặp lại.','Vào cửa ▪︎ earplugs miễn phí','OBJoff','OBJoff','slate','OBJoff đây, tối đó gặp nhé.'],
  ['pianomuon','music','Nhạc','Piano Muộn','1CAFKmNPymRS9P7vNRnPGxHwPYf0SXorw','Quận 1','5,2','CN, 12.07','Chủ Nhật, 12 tháng 7','22:00','300.000₫',11,'Một cây đàn, một người chơi, đèn tắt gần hết. Bốn mươi lăm phút.','1 set ▪︎ một ly vang','Nhà Piano','Nhà Piano','slate','Nhà Piano chào bạn. Đến trước 21:45 nhé, vào trễ phải chờ hết bài.'],

  ['banrieng','supper','Supper club','Bàn Riêng','1koPFwcKRxI9VlbBZCJSdwLW_xya9YJU5','Bình Thạnh','2,1','Th 4, 15.07','Thứ Tư, 15 tháng 7','19:30','1.500.000₫',4,'Sáu chỗ, không đăng công khai. Minh nấu riêng cho vài người quen của người quen.','7 món ▪︎ rượu vang chọn riêng','Minh, @bepnho.saigon','Minh','ember','Bạn được mời vào bàn này. Rủ thêm 1 người cũng được nhé.'],
];


const ORG = {
  bepnho: { name: 'Bếp Nhỏ', ig: '@bepnho.saigon', desc: 'Minh nấu cho người lạ từ 2021, bắt đầu bằng vài cái bàn trong ga-ra. Mỗi tối một thực đơn, đi chợ Bà Chiểu lúc sáu giờ sáng.' },
  comnha: { name: 'Cơm Nhà Mai', ig: '@comnhamai', desc: 'Mai dọn bữa tối trên sân thượng nhà mình, nấu kiểu cơm nhà miền Trung. Tám chỗ, không hơn.' },
  bandai: { name: 'Bàn Dài', ig: '@bandai.supper', desc: 'Một cái bàn dài, những người chưa từng gặp. Bàn Dài dọn bữa cho người lạ ngồi cạnh nhau từ 2022.' },
  phokhuya: { name: 'Phở Khuya', ig: '@phokhuya', desc: 'Tùng bán phở lúc nửa đêm cho người đi làm ca muộn và người không ngủ được. Mười hai ghế nhựa, một nồi nước.' },
  vuonsau: { name: 'Vườn Sau', ig: '@vuonsau.collective', desc: 'Nhóm bạn nấu ăn trong khu vườn sau nhà ở Gò Vấp. Rau hái tại vườn, mưa thì dời vô hiên.' },
  orbit: { name: "Rue Miche L'Édition", ig: '@ruemiche', desc: "Cửa hàng và không gian sự kiện của các nhà thiết kế Việt. L'Édition là chuỗi buổi diễn giới thiệu bộ sưu tập mới, tổ chức tại xưởng." },
  aeie: { name: 'AEIE Studios', ig: '@aeie.studios', desc: 'Studio thời trang ở Thảo Điền, thành lập 2018. Tinh thần: bình thường hóa những điều khác thường.' },
  fanci: { name: 'Fanci Club', ig: '@fanci.club', desc: 'Thương hiệu của Duy Trần, cùng quỹ đạo sáng tạo với AEIE. Đồ may đo, thử tại chỗ.' },
  compound: { name: 'Compound Garment', ig: '@compound.garment', desc: 'Streetwear địa phương, Quận 1. Drop giới hạn, thường bán trên sân thượng lúc chiều muộn.' },
  motlop: { name: 'Mãi Mãi', ig: '@maimai.mag', desc: 'Tạp chí về chất liệu và nghề thủ công Việt. Mãi bám rễ nơi ta đến, mãi vươn về nơi ta tới.' },
  vungtrang: { name: 'Nguyen Art Foundation', ig: '@nguyenartfoundation', desc: 'Quỹ nghệ thuật đương đại tại HCMC, sưu tập và trưng bày nghệ sĩ Việt trong và ngoài nước.' },
  sonmai: { name: 'Galerie Quỳnh', ig: '@galeriequynh', desc: 'Phòng tranh đương đại lâu đời của thành phố, chuyên nghệ sĩ Việt và quốc tế.' },
  khongnguoi: { name: 'Lâm', ig: '@khongnguoi', desc: 'Lâm chụp thành phố không người trong sáu năm, đi bộ lúc năm giờ sáng. Đây là triển lãm cá nhân đầu tiên.' },
  noigiay: { name: 'Zone Publishing', ig: '@zone.publishing', desc: 'Nhà làm zine và sách nhỏ, tổ chức các buổi nói chuyện về nghề in và giấy.' },
  phong302: { name: 'Phòng 302', ig: '@phong302', desc: 'Không gian nghệ thuật trong một căn hộ tập thể cũ ở Quận 5. Mỗi kỳ một nhóm nghệ sĩ.' },
  chieucham: { name: 'Yentown', ig: '@yentown.saigon', desc: 'Sân chơi phức hợp nghệ thuật ở Quận 1. Chiều Chậm là chuỗi buổi DJ thư giãn cuối tuần.' },
  jazzgac: { name: 'Gác', ig: '@jazzogac', desc: 'Gác gỗ hai mươi chỗ trên một con hẻm Quận 1. Jazz mộc, không micro, mỗi tuần một nhóm.' },
  bangcoi: { name: 'Băng Cối', ig: '@bangcoi.club', desc: 'Câu lạc bộ nghe nhạc từ băng cối qua dàn loa cổ. Không điện thoại trong phòng nghe.' },
  modular: { name: 'OBJoff', ig: '@objoff', desc: 'Tập thể nhạc điện tử thử nghiệm với dàn máy modular. Không set nào lặp lại.' },
  pianomuon: { name: 'Nhà Piano', ig: '@nhapiano', desc: 'Một căn phòng, một cây đàn. Nhà Piano tổ chức recital muộn cho tối đa mười hai người.' },
};

const STATUS = {
  bandai: { cancelled: true, cancelledHoursAgo: 5 },
  phokhuya: { endedHoursAgo: 10 },
  motlop: { endedHoursAgo: 74 },
  fanci: { soldOut: true },
};

const INVITE_ONLY = { banrieng: true };

const ORG_STATS = {
  bepnho: { since: 2021, count: 47 }, comnha: { since: 2023, count: 12 }, bandai: { since: 2022, count: 31 },
  phokhuya: { since: 2024, count: 8 }, vuonsau: { since: 2025, count: 3 },
  orbit: { since: 2020, count: 9 }, aeie: { since: 2018, count: 22 }, fanci: { since: 2023, count: 6 },
  compound: { since: 2021, count: 15 }, motlop: { since: 2024, count: 4 },
  vungtrang: { since: 2019, count: 18 }, sonmai: { since: 2015, count: 60 }, khongnguoi: { since: 2026, count: 1 },
  noigiay: { since: 2022, count: 9 }, phong302: { since: 2023, count: 7 },
  chieucham: { since: 2021, count: 33 }, jazzgac: { since: 2020, count: 52 }, bangcoi: { since: 2022, count: 14 },
  modular: { since: 2023, count: 11 }, pianomuon: { since: 2019, count: 26 },
};

// Paid placement: organizers can pay to list in a second category (max 2)
const CAT2 = {
  motlop: { key: 'gallery', label: 'Phòng tranh' },
  aeie: { key: 'gallery', label: 'Phòng tranh' },
  chieucham: { key: 'supper', label: 'Supper club' },
};

const TODAY = new Date(2026, 6, 8);

// Approximate district centers in Ho Chi Minh City. The demo data only has a
// district name per event (no street address), so each event's coordinates
// are the district center plus a small deterministic offset — enough to open
// the right neighborhood in Google Maps and compute a real, if approximate,
// distance once the browser shares the user's location.
const AREA_COORDS = {
  'Bình Thạnh': [10.8034, 106.7108],
  'Quận 1': [10.7769, 106.7009],
  'Quận 3': [10.7756, 106.6917],
  'Quận 4': [10.7593, 106.7033],
  'Quận 5': [10.7551, 106.6667],
  'Gò Vấp': [10.8386, 106.6652],
  'Thảo Điền': [10.8033, 106.7378],
};

function areaCoords(area) {
  const match = Object.keys(AREA_COORDS).find(name => area.includes(name));
  return AREA_COORDS[match] || AREA_COORDS['Quận 1'];
}

// A tiny seeded PRNG — deterministic so an event's coordinates never jump
// around between renders.
function seededJitter(key) {
  let seed = 0;
  for (const ch of key) seed = (seed * 31 + ch.charCodeAt(0)) % 9973;
  const a = (seed % 1000) / 1000 - 0.5;
  const b = ((seed * 7) % 1000) / 1000 - 0.5;
  return [a * 0.012, b * 0.012]; // roughly ±650m
}

export function haversineKm(a, b) {
  if (!a || !b || a.lat == null || a.lng == null || b.lat == null || b.lng == null) return null;
  const R = 6371;
  const dLat = (b.lat - a.lat) * Math.PI / 180;
  const dLng = (b.lng - a.lng) * Math.PI / 180;
  const lat1 = a.lat * Math.PI / 180;
  const lat2 = b.lat * Math.PI / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

export function mapsUrl(ev) {
  if (ev.lat == null || ev.lng == null) return null;
  return 'https://www.google.com/maps/search/?api=1&query=' + ev.lat + ',' + ev.lng;
}

export function img(id) {
  return '/photos/' + id;
}

export function bg(url, extra) {
  return Object.assign({ backgroundImage: 'url(' + url + ')', backgroundSize: 'cover', backgroundPosition: 'center', borderRadius: 14, filter: 'saturate(0.92) contrast(1.07)' }, extra || {});
}

function relDays(dayShort) {
  const m = dayShort.match(/(\d{1,2})\.(\d{2})/);
  if (!m) return null;
  const d = new Date(2026, parseInt(m[2], 10) - 1, parseInt(m[1], 10));
  return Math.round((d - TODAY) / 86400000);
}

export function untilLabel(n) {
  return n === 0 ? 'Hôm nay' : n === 1 ? 'Ngày mai' : 'Còn ' + n + ' ngày';
}

export function agoLabel(h) {
  return h < 24 ? (h <= 1 ? '1 giờ trước' : h + ' giờ trước') : (Math.floor(h / 24) === 1 ? '1 ngày trước' : Math.floor(h / 24) + ' ngày trước');
}

export const EVENTS = ROWS.map((r, idx) => {
  const st = STATUS[r[0]] || {};
  const until = relDays(r[7]);
  const heroPhoto = LOCAL_PHOTOS[idx % LOCAL_PHOTOS.length];
  const gallery = [img(heroPhoto)];
  for (let i = 0; i < 7; i++) gallery.push(img(LOCAL_PHOTOS[(idx * 5 + i) % LOCAL_PHOTOS.length]));
  const orgGallery = [img(heroPhoto)];
  for (let i = 0; i < 21; i++) orgGallery.push(img(LOCAL_PHOTOS[(idx * 3 + i) % LOCAL_PHOTOS.length]));
  const org = ORG[r[0]] || { name: r[15], ig: '', desc: '' };
  const orgStat = ORG_STATS[r[0]] || { since: 2026, count: 1 };
  const trusted = orgStat.count >= 20;
  const [baseLat, baseLng] = areaCoords(r[5]);
  const [jitterLat, jitterLng] = seededJitter(r[0]);
  return {
    key: r[0], catKey: r[1], cat: r[2], name: r[3],
    img: img(heroPhoto),
    lat: baseLat + jitterLat, lng: baseLng + jitterLng,
    meta: r[5] + ' ▪︎ ' + r[6] + ' km ▪︎ ' + r[7].split(', ')[0] + ', ' + r[9],
    where: r[5] + ' ▪︎ ' + r[6] + ' km từ bạn ▪︎ ' + r[8] + ' ▪︎ ' + r[9],
    when: r[7] + ' ▪︎ ' + r[9],
    price: r[10], seats: 'Còn ' + r[11] + ' chỗ', seatsLong: 'Còn ' + r[11] + ' chỗ', urgent: r[11] <= 5,
    desc: r[12], included: r[13], host: r[14], hostShort: r[15],
    palette: PALETTES[r[16]], greeting: r[17],
    gallery, orgGallery, orgName: org.name, orgIg: org.ig, orgDesc: org.desc,
    orgSince: orgStat.since, orgCount: orgStat.count, orgTrusted: trusted,
    cancelled: !!st.cancelled, cancelledHoursAgo: st.cancelledHoursAgo != null ? st.cancelledHoursAgo : null, endedHoursAgo: st.endedHoursAgo != null ? st.endedHoursAgo : null,
    soldOut: !!st.soldOut, inviteOnly: !!INVITE_ONLY[r[0]],
    cat2Key: (CAT2[r[0]] || {}).key || null, catDisplay: r[2] + (CAT2[r[0]] ? ' ▪︎ ' + CAT2[r[0]].label : ''),
    until, untilLabel: until != null ? untilLabel(until) : '', agoLabel,
  };
});

export function findEvent(key) {
  return EVENTS.find(e => e.key === key) || EVENTS[0];
}

export const CREATE_PALETTES = [
  { key: 'concrete', name: 'Đất', bg: '#C9A98C', text: '#1B1916', accent: '#1B1916' },
  { key: 'night', name: 'Rừng', bg: '#7E9077', text: '#F7F4EC', accent: '#F7F4EC' },
  { key: 'slate', name: 'Mực', bg: '#4A5A66', text: '#F7F4EC', accent: '#F7F4EC' },
  { key: 'ember', name: 'Nghệ', bg: '#D9A03F', text: '#1B1916', accent: '#1B1916' },
  { key: 'studio', name: 'Gạch', bg: '#B0573C', text: '#F7F4EC', accent: '#F7F4EC' },
  { key: 'smoke', name: 'Khói', bg: '#8C8577', text: '#F7F4EC', accent: '#F7F4EC' },
];

export const CREATE_PHOTO_SLOT_IDS = LOCAL_PHOTOS.slice(0, 8);
