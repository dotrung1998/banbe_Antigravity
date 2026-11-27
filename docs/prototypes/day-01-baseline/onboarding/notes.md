# Onboarding & first-run · Ngày 1/8 · Cụm 1/5

Bản dựng **mới từ ảnh thật** theo `docs/prototypes/decisions/day-01.json` (`onb-base = fresh`). Không sửa `src/`, `ios/` hay migration; không deploy. Đây là một stage độc lập trong `docs/prototypes/day-01-baseline/onboarding/`.

## Chạy

```bash
python3 -m http.server 4173 --bind 127.0.0.1 --directory docs/prototypes
# http://127.0.0.1:4173/day-01-baseline/onboarding/index.html
```

`?embed=1` là chế độ 1:1 không thanh stage, dùng cho iframe và capture. `#b1`…`#b8` mở thẳng từng bước; `#b5` là Dành cho bạn.

## Giữ gì

**Từ vỏ chung:** stage, thanh 4 khung 390 / 834 / 1194 / 1440 + Cả 4, nút **Làm lại**, thanh 5 cụm, deep link `#bN`, rail 8 bước ở 1194+, nền giấy/mực/serif của app, `sessionStorage` key `bb:onboarding:state`. Không dùng `position: fixed`; foot dính trong vùng cuộn.

**Từ bản v5 (chỉ ngữ pháp, không copy pixel):** cửa vào tối, ảnh thật xoè như một tấm bưu thiếp, một câu hỏi một màn, một “Dành cho bạn” có sự kiện thật. Bỏ cột 480 px giữa tờ giấy, bỏ tour dài và mọi pixel của v5.

## Đổi gì

- **8 bước cho 5 nhóm màn**: Chào → 3 câu → Dành cho bạn → 2 consent → Đăng nhập. Ba câu và hai consent mỗi thứ một màn, để mỗi màn có một việc rõ.
- **Chào không phải tờ khai**: không input, không tài khoản, không email. Chỉ một cửa vào + 7 buổi thật đang mở + hai lựa chọn (Bắt đầu / Xem trước) + ba lối khách Home · Map · Sự kiện.
- **Consent và đăng nhập sau giá trị**: reveal đứng trước; bản tin và chế độ tổ chức mặc định **tắt**, có “Để sau”; đăng nhập là bước cuối, có nút khách.
- **Bỏ qua vẫn xem được**: “Bỏ qua cả 3 câu” đưa thẳng tới reveal; từ Chào, reveal và Đăng nhập đều có link thật tới Home/Map/Sự kiện trên `www.banbe.app`, không cần tài khoản.
- **Bốn khung là bốn bố cục thật**, không phải một cột điện thoại được kéo giãn: 390 một cột; 834 hai cột (bước + bằng chứng); 1194 ba vùng (rail · bước · bằng chứng); 1440 cùng ba vùng trong cột đọc 1280. Tất cả bằng `@container screen`; chỉ có một `@media` cho `prefers-reduced-motion`.
- **Sửa tại chỗ, không lùi bước**: ba dòng “Sở thích / Thời gian / Ngân sách” ở bước 5 và hai dòng tóm tắt “Bản tin / Chế độ tổ chức” ở bước 8 mở một **sheet từ đáy** ngay trên bước hiện tại. Chọn xong bấm **Xong**, chạm nền hoặc **Esc** là đóng; focus trả về đúng nút; không có `href="#bN"`, không phải bấm Tiếp lại. “Chọn” khi Sở thích trống cũng mở sheet.
- **Dữ liệu thật thay cho màn hình bịa**: 7 sự kiện production, ảnh cover thật, giờ/giá/khu vực thật. Card sự kiện mở một **màn demo trong prototype**, ghi rõ đang ở bước onboarding nào; chỉ link “Mở trên app thật” mới rời sang production. Bản tin là một **ví dụ dựng từ dữ liệu thật**, không phải ảnh chụp email.

## Vì sao

Cụm này là cửa vào. Nếu 834/1194/1440 chỉ là một cột 390 đặt giữa giấy thì cả thang prototype mất căn cứ. Vì vậy mỗi khung có một việc riêng: 390 đọc như điện thoại; 834 cho câu hỏi và bằng chứng đứng cạnh nhau; 1194 thêm rail để thấy mình đang ở đâu; 1440 giữ nhịp đọc bằng cột 1280. Welcome phải là một cánh cửa, không phải biểu mẫu; consent/login chỉ có nghĩa sau khi người dùng đã thấy giá trị.

## 8 bước

| # | Nhóm | Nội dung | Điểm thị giác có chủ đích |
| --- | --- | --- | --- |
| 1 | Chào | Cửa vào, 7 buổi đang mở, 2 lựa chọn, 3 link khách | Nền tối + collage 3 ảnh thật + seal vàng “Dành cho bạn” + chỉ mục tuần bên phải |
| 2 | 3 câu · 1 | Bạn thấy gì vui? 5 loại, chọn nhiều | 5 tile emoji + số buổi thật + 3 card sự kiện phản ứng ngay |
| 3 | 3 câu · 2 | Bạn thường rảnh khi nào? 4 lựa chọn | 4 tile + dải 6 ngày có số buổi; ngày khớp sáng lên |
| 4 | 3 câu · 3 | Giá vé bao nhiêu thì thoải mái? 4 mức | Cây thước giá với 7 chấm thật; dải “đến mức bạn chọn” tô tới đúng chỗ |
| 5 | Dành cho bạn | Reveal không bao giờ rỗng; 7 buổi thật | Masthead báo giấy + lead card lớn + 6 dòng còn lại + card 3 dòng câu trả lời + dải tuần |
| 6 | Consent · bản tin | Một email thứ Năm, mặc định tắt, “Để sau” | Một tờ email giấy dựng từ 3 sự kiện thật, không phải screenshot |
| 7 | Consent · tổ chức | Chế độ tổ chức, mặc định tắt, “Để sau” | 3 việc host làm được, đánh số 01–03, không tạo gì sẵn |
| 8 | Đăng nhập | Google / mã qua email / mật khẩu; khách vẫn xem tiếp | Cửa sổ vé + danh sách “Bạn giữ lại gì” + tóm tắt lựa chọn bên phải |

## Bố cục

| Khung | Cột | Ghi chú |
| --- | --- | --- |
| 390×844 | 1 | Bước ở trên, bằng chứng cuộn ở dưới; foot dính trong scroller; welcome cao 683 px, chỉ mục tuần ló ra ở đáy |
| 834×1194 | 2 | `1.17fr / 0.83fr`: bước trái, bằng chứng phải; main cao hết 1194 nên welcome đặt CTA ở đáy, login đặt form trên và lối khách ở đáy |
| 1194×834 | 3 | rail 178 px · bước · bằng chứng 356 px; rail/main/evidence cuộn riêng; reveal để foot tĩnh để thấy danh sách thay vì bị foot che |
| 1440×900 | 3 | Cùng ba vùng trong `width: 1280px`, rail 200 + bước + evidence 400, lề giấy 80 px hai bên |

**Sheet sửa tại chỗ** dùng cùng `@container screen`: rộng 390 ở 390, 560 từ 834, 600 từ 1194/1440; dính đáy thiết bị, cao tối đa 86%, option ≥52, nút đóng 44, Xong 52; scrim phủ riêng khung.

## Dữ liệu thật

7 sự kiện đang mở trên production, nhóm F của đợt test data v2.3 (28.11–03.12.2026). Tên/ngày/giờ đã đối chiếu trên production ngày **2026-11-27** qua `https://www.banbe.app/api/photo-share?eid=<id>` (`og:description`); giá/loại/khu vực/cover lấy từ `supabase/drafts/v23-testdata/group-f-events.json`; cả 7 trang `/event/<id>` trả 200 ngày 2026-11-27.

| id | Tên | Loại | Ngày · giờ | Khu vực | Giá | Cover |
| --- | --- | --- | --- | --- | --- | --- |
| `chophien` | Chợ Phiên Sân Thượng | Pop-up | T7 28.11 · 16:00 | Quận 1 | 0₫ (Miễn phí) | `DSCF7597.jpg` |
| `bunchay` | Bữa Chay Sân Gạch | Supper club | T7 28.11 · 18:30 | Quận 10 | 380.000₫ | `DSCF6107.jpg` |
| `saxsang` | Sax Buổi Sáng | Nhạc | CN 29.11 · 10:00 | Thảo Điền | 150.000₫ | `DSCF4282.jpg` |
| `tranhtoi` | Trăng Tối Acoustic | Nhạc | T2 30.11 · 20:00 | Quận 1 | 220.000₫ | `DSCF4212.jpg` |
| `gomxanh` | Gốm Xanh Biên Hoà | Phòng tranh | T3 01.12 · 18:00 | Quận 1 | 120.000₫ | `DSCF2539.jpg` |
| `phimcu` | Phim Cũ, Ảnh Mới | Phòng tranh | T4 02.12 · 17:00 | Quận 5 | 90.000₫ | `DSCF2023.jpg` |
| `maydo` | Một Buổi May Đo | Thời trang | T5 03.12 · 15:00 | Bình Thạnh | 650.000₫ | `DSCF4254.jpg` |

Ảnh gốc nằm trong `public/photos/` của app; bản trong `photos/` đã nén còn 170–262 KB. Đếm thật dùng trong UI: 1 supper club, 2 nhạc, 2 phòng tranh, 1 thời trang, 1 pop-up; 3 buổi cuối tuần, 4 buổi tối; 4 buổi ≤ 200.000₫, 6 buổi ≤ 600.000₫, 7 buổi tất cả. Các mức này khớp `src/lib/eventPrefs.js` (`low` 200.000, `medium` 600.000, `flexible` không giới hạn).

## Trạng thái & tương tác

- Mặc định: `interests: []`, `availability: []`, `budget: null`, `digest: false`, `hosting: false`, `method: 'code'`, email/password rỗng, chưa gửi.
- Chọn tile loại/giờ: bật/tắt nhiều lựa chọn; số buổi và 3 card bên cạnh đổi ngay. Chọn ngân sách: một mức, bấm lại để bỏ; thước giá tô tới mức và làm mờ chấm vượt mức.
- Reveal: buổi khớp lên trước và có nhãn “Khớp”; nếu không có buổi nào khớp cả ba lựa chọn, vẫn hiện đủ 7 buổi gần nhất kèm câu giải thích. Không bao giờ rỗng. Ba câu trả lời là **một card 3 dòng** cùng bề rộng; “Chọn/Sửa” nằm trong cột phải, căn giữa dòng, không còn là các chip rời co theo nội dung.
- **Sửa tại chỗ**: ba action recap ở bước 5 và hai action tóm tắt ở bước 8 mở sheet từ đáy, giữ nguyên bước; option/switch cập nhật state và recap ngay; “Bỏ chọn tất cả”/“Bỏ giới hạn” xoá lựa chọn; Xong/scrim/Esc/X đóng, Tab bị giữ trong sheet, focus trả về nút đã mở.
- **Sự kiện mở màn demo tại chỗ**: mọi card (welcome, ba câu, reveal) mở một màn demo trong khung, không đẩy người xem sang production. Màn demo ghi rõ “Demo trong prototype · không phải app thật” và “Bước N/8 · tên bước”, giữ ảnh/ngày/giờ/khu vực/giá thật, có “Quay lại onboarding” (và Esc) cùng một link rời có chủ đích “Mở trên app thật”. Đóng trả focus về card đã bấm.
- Consent: hai switch thật (`role="switch"`, `aria-checked`), mặc định tắt, có “Để sau”; tóm tắt lựa chọn hiện ở bước Đăng nhập.
- Đăng nhập: chọn mã qua email hoặc mật khẩu; email phải đúng định dạng; nút bị khoá tới khi hợp lệ; Enter ở cả email và mật khẩu; Esc trong input chỉ blur. Submit chỉ hiện ghi chú “bản xem trước”, **không gửi email, không tạo phiên**; Google cũng chỉ hiện ghi chú.
- **Làm lại**: xoá key `bb:onboarding:state`, xoá email/mật khẩu/ghi chú/lỗi, tắt cả switch, bỏ mọi lựa chọn, về `#b1`. Stage gọi `reset()` rồi `go(1)`. `reset()` cũng gọi `renderLogin()` để dọn method về “Mã qua email”, ẩn password field và khoá submit dù bước 8 đang ẩn.
- Deep link `#b1`…`#b8`; Back của trình duyệt đi lại được; Esc lùi một bước khi không ở trong input.
- Hợp đồng JS: `window.bbScreen = { steps: 8, render, reset }`; stage gọi `render(n)` và `reset()`.

## Liên kết cụm

- **Onboarding** là link local sống duy nhất (`../onboarding/index.html`, `aria-current="page"`).
- **Khám phá, Sự kiện, Của tôi, Host**: tại **2026-11-27**, `docs/prototypes/day-01-baseline/` chỉ có `onboarding`, `frames`, `research` và README; **không có scaffold** `discover/`, `event/`, `me/`, `host/`. Vì vậy nav giữ fallback app thật + nhãn `app thật` (target `_blank`), viết tay để tránh HEAD 404 vào file chưa có. Khi scaffold xuất hiện, trỏ `href` local + `data-app` để stage tự phát hiện.
- Welcome, Reveal, Đăng nhập mỗi màn có 3 link khách Home · Map · Sự kiện; tổng 9 link, tất cả mở app thật, không cần tài khoản.
- **Đã kiểm 3 link cụm khác bắt buộc — và cả Host — bằng request ngày 2026-11-27:**

| Cụm | URL kiểm | Kết quả | Ngày |
| --- | --- | --- | --- |
| Khám phá | https://www.banbe.app/ | 200 | 2026-11-27 |
| Sự kiện | https://www.banbe.app/ | 200 | 2026-11-27 |
| Của tôi | https://www.banbe.app/schedule | 200 | 2026-11-27 |
| Host | https://www.banbe.app/projects | 200 | 2026-11-27 |

4/4 link nav trả 200 (3 URL unique); 9 link khách và 7 trang sự kiện cũng 200. Không có scaffold cục bộ nên chưa có điều hướng local sang bốn cụm này.

## Nguồn

### 1. Apple Human Interface Guidelines — Onboarding

- URL: https://developer.apple.com/design/human-interface-guidelines/onboarding — đọc **2026-11-27**.
- Học: onboarding nên nhanh, có thể bỏ qua, không lặp lại điều đã bỏ qua; chỉ hỏi khi thật cần, hoãn thiết lập không thiết yếu.
- Giữ: 3 câu ngắn, nút bỏ qua, consent mặc định tắt, lối khách.
- Bỏ: tour bắt buộc/giải thích dài trước khi thấy giá trị.

### 2. NN/g — Onboarding Tutorials vs. Contextual Help

- URL: https://www.nngroup.com/articles/onboarding-tutorials/ — xuất bản 2023-02-12, đọc **2026-11-27**.
- Học: tutorial dài thường bị bỏ qua và dễ quên; cho dismiss + recall; progressive disclosure.
- Giữ: một câu một màn, bằng chứng ngay cạnh câu hỏi, rail/back để xem lại; reveal thật thay cho lời hứa.
- Bỏ: tour 6 chương, không ép đọc, không khoá đường ra.

### 3. Trong nhà — bản v5 standalone

- URL/tệp: `docs/prototypes/archive/banbe-onboarding-v5-standalone.html` — đọc **2026-11-27**.
- Giữ: cửa vào tối, ảnh thật xoè, một câu hỏi một màn, “Dành cho bạn” có sự kiện thật.
- Bỏ: cột 480 px giữa tờ giấy, tour dài, mọi pixel của v5. Đây là **ngữ pháp**, không phải bản copy.

## Đã kiểm

| Hạng mục | Cách kiểm | Kết quả |
| --- | --- | --- |
| 4 khung × 8 bước | Chromium/Playwright, viewport đúng 390×844, 834×1194, 1194×834, 1440×900; `?embed=1&capture=1`; mỗi bước đo `scrollWidth === clientWidth` | **Pass** cả 32 tổ hợp; không ảnh vỡ; đúng 1 section hiện |
| Làm lại từ 6, 7, 8 | Mỗi lần: chọn 2 loại + cuối tuần + medium; bật cả 2 consent; chọn mật khẩu và điền email/password; về đúng bước 6/7/8 rồi bấm `[data-reset]` | **Cả 3 pass**: `#b1`, key null, 0 preference `aria-pressed`, 0 switch on, email/password rỗng, method về mã, password field ẩn, submit disabled, note/error ẩn; reveal trở lại 3 dòng “Chưa chọn” |
| Deep link + Back + Esc | `#b2` mở bước 2; Tiếp → 3; `goBack()` → 2; Esc → 1 | Pass |
| Link cụm | 5 nav: 1 local + 4 app thật có nhãn; `curl` 3 URL unique của nav (Home, Schedule, Projects) + 7 trang sự kiện | Pass: 4/4 link nav 200, vượt mức 3; tất cả 200 ngày 2026-11-27 |
| Console | Bắt `console.error` + `pageerror` ở cả 4 khung × 8 bước và 3 lần reset từ 6/7/8 | **0 lỗi** (sau khi viết tay fallback nav, không còn HEAD 404) |
| Luồng | Music + weekends + low → reveal 7 buổi (1 khớp), card 3 dòng câu trả lời; bật digest/hosting; login mật khẩu; submit | Pass; note prototype hiện đúng |
| Bàn phím + chạm | Cả 8 bước ở 390 1:1: 0 control hiện < 44 px; rail/card câu trả lời/method đặt min-height 44; Tab tới “Chọn” có outline 2 px clay; Enter ở email/mật khẩu; Esc | Pass (chưa test screen reader) |
| Card câu trả lời | 390/834/1194/1440, cả trạng thái mặc định và đã chọn; đo bề rộng card, chiều cao action, `scrollWidth` | **Pass 8/8**: 3 dòng cùng bề rộng, action 44 px thẳng cột và giữa dòng; 1194/1440 không co (đã thêm `flex: none`) |
| Nhãn control + cột action (audit trước khi đổi action) | 32 tổ hợp bước × khung, state đã trả lời; quét mọi `button`/`a[href]`/`[role="switch"]` hiện, đo tâm nhãn so với tâm control và top gap; đo left/right của action; riêng bước 8 thêm state trộn `digest: true`, `hosting: false` | **Pass 32/32**: 0 nhãn dính mép trên, 0 cột action lệch; summary 4/4 right spread 0, action 44 px; không tràn ngang |
| Cột action sau khi đổi sang button | 4 khung × 3 recap + 2 summary, state trộn; đo chiều cao, tâm nhãn, right spread và tràn ngang | **Pass**: recap 4/4 (3 button/khung) + summary 4/4 (2 button/khung); 44 px, tâm lệch 0, right spread 0; không tràn |
| Sheet chỉnh nhanh | 4 khung × 5 nguồn (interests, availability, budget, digest, hosting): đo rộng/đáy/top, option ≥44, Xong/scrim/Esc/X, Tab/Shift+Tab, focus trả về, step không đổi; 390 đổi từng nhóm, “Bỏ giới hạn”, scroll giữ nguyên, reset | **Pass 20/20 mở**; 390 thao tác pass; focus trap; 0 lỗi console/page; không tràn ngang; stage thật 834/1440 cũng bám đáy thiết bị |
| Reduced motion | Chụp với `prefers-reduced-motion: reduce`; không animation vào | Pass, bản tĩnh vẫn đọc được |
| Frame 6/7 mới | 8 ảnh consent ở 390/834/1194/1440: `scrollWidth`, ảnh vỡ, section, control <44 ở 390 1:1 | **Pass 8/8**; consent 390 có 0 control <44 |
| Frame 3/4 mới | 8 ảnh bước 3/4 ở 390/834/1194/1440: `scrollWidth`, ảnh vỡ, section, control <44 ở 390 1:1 | **Pass 8/8**; nhóm 3 câu hỏi đủ 2/3/4 ×4; toàn bộ 32/32 |
| Demo sự kiện | Mở card đầu tiên ở 5 bước có sự kiện × 4 khung (20 lần); đo `scrollWidth`, control <44, nhãn bước, Esc, đóng và focus | **Pass 20/20**; không tràn ngang, 0 control <44, nhãn đúng bước, Esc đóng, focus về card |
| Ảnh | 32 ảnh bước (8 bước × 4 khung) + 1 overview contact sheet 8×4 = **33 PNG**; 8 bước 1–8; bước 5 chụp ở trạng thái đã trả lời (Chưa chọn / Buổi tối, Ban ngày / Đến 600.000đ) bằng `capture-step5.mjs` | Đã xem contact sheet + 3/4/consent + cả 4 frame bước 5; không soi từng pixel từng file |

Lệnh capture cuối (preview đang ở cổng 4174):

```bash
# 28 frame còn lại; bước 5 chụp riêng bằng capture-step5.mjs
node docs/prototypes/shared/capture-stage.mjs \
  --url http://127.0.0.1:4174/day-01-baseline/onboarding/index.html \
  --out docs/prototypes/day-01-baseline/frames \
  --cluster onboarding --steps 1,2,3,4,6,7,8

node docs/prototypes/day-01-baseline/onboarding/capture-step5.mjs \
  --url http://127.0.0.1:4174/day-01-baseline/onboarding/index.html

node docs/prototypes/day-01-baseline/onboarding/overview.mjs

node docs/prototypes/day-01-baseline/onboarding/check-frames.mjs \
  --url http://127.0.0.1:4174/day-01-baseline/onboarding/index.html
```

## Chưa kiểm

- **Sheet sửa tại chỗ không nằm trong 32 frame**: đã kiểm hình học/tương tác ở 4 khung và xem nhanh ảnh 390/834; bộ nộp vẫn chỉ có trạng thái đóng, chưa chụp sheet thành frame chính thức.
- **Chưa chạy trên iPhone/iPad/Safari thật**; mới là Chromium headless ở 4 viewport. Chưa kiểm touch, safe-area, scroll momentum, font fallback trên iOS.
- **Chưa test screen reader/VoiceOver**, tương phản từng cặp màu, hay thứ tự đọc đầy đủ. Đã kiểm Tab/Enter/Esc và outline; chưa kiểm ARIA live bằng AT.
- **Đăng nhập chưa nối backend**: không gửi mã, không OAuth, không tạo phiên; chỉ là ghi chú prototype. Google/mã/mật khẩu không gọi mạng.
- **Chưa có scaffold cục bộ cho bốn cụm khác**: nav đang trỏ app thật bằng fallback viết tay (đã kiểm 200); chưa có điều hướng local sang Khám phá/Sự kiện/Của tôi/Host.
- **Dữ liệu là ảnh chụp 2026-11-27**: nếu production đổi/xoá 7 sự kiện test, card và link có thể khác; chưa kiểm lại sau ngày đó.
- **Chưa chụp trạng thái có buổi khớp**: frame reveal chụp trạng thái đã trả lời như ảnh user (Sở thích: Chưa chọn; Thời gian: Buổi tối, Ban ngày; Ngân sách: Đến 600.000đ), không phải trạng thái có 1 buổi khớp; trạng thái khớp vẫn chỉ kiểm bằng script.
- **Màn demo sự kiện không có trong 32 frame**: đây là trạng thái mở từ card, đã kiểm bằng script ở cả 4 khung nhưng chưa chụp thành ảnh.
- **834 là iPad dọc 1194 cao**: khoảng trống dưới form login (form trên, lối khách dưới) là chủ ý; consent 6/7 cũng đặt form trên, bằng chứng dưới nên còn thoáng. Chưa xem trên iPad thật để quyết định có giữ hay không.
- **Ảnh sự kiện**: là cover thật từ `public/photos/`, nhưng chưa xác nhận quyền/credit với host; chỉ ghi nguồn tệp.

## Tệp

```text
docs/prototypes/day-01-baseline/onboarding/
  index.html          # stage + 8 section + nav/rail/foot + sheet layer
  screen.css          # 390 / 834 / 1194 / 1440 bằng @container + sheet
  screen.js           # data 7 sự kiện, state, render, reset, demo, sheet
  overview.mjs        # dựng contact sheet 8×4 từ 32 frame
  check-frames.mjs    # audit 32 frame live + 33 PNG
  capture-step5.mjs   # chụp riêng bước 5 ở trạng thái đã trả lời
  notes.md            # tệp này
  photos/             # 7 cover thật đã nén (DSCF7597, 6107, 4282, 4212, 2539, 2023, 4254)
docs/prototypes/day-01-baseline/frames/
  onboarding-{01,02,03,04,05,06,07,08}-{390,834,1194,1440}.png   # 32 frame
  onboarding-overview-1440.png                                    # contact sheet 8×4
  capture.md
```
