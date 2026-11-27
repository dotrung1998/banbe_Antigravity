# 10 repo trong video "10 GitHub Repos to 10x Your AI Motion Graphics" — cái nào dùng được cho banbe

Nghiên cứu ngày **2026-11-27**. Video: *10 GitHub Repos to 10x Your AI Motion Graphics*, Matt Penny | Applied AI,
đăng 2026-11-09, 3:19, 171k lượt xem ([youtube.com/watch?v=aD9X6Lc3dVk](https://www.youtube.com/watch?v=aD9X6Lc3dVk)).
Chương: Intro 0:00 · Repo 1 0:44 · Repo 2 2:34 · Repo 3 4:00 · Repo 4 4:53 · Repo 5 7:04 · Repo 6 8:13 ·
Repo 7 8:58 · Repo 8 9:56 · Repo 9 10:49 · Repo 10 11:38.

Video nói về **motion graphics làm bằng code** (Claude viết React/p5/three, headless browser chụp từng frame, ffmpeg
ghép MP4) — không phải model sinh video. Đó là lý do nó *có thể* dùng được: mọi frame là code chạy trên ảnh thật của
app, nên không có chuyện AI bịa ra một màn hình không tồn tại.

## banbe cần gì (2 việc khác nhau)

| Việc | Sản phẩm | Công cụ đúng |
| --- | --- | --- |
| A. Onboarding cinematic, to, rõ, bằng **ảnh thật trong app** | motion study (MP4 + frame stills) để chốt nhịp/hướng chuyển, rồi dựng lại bằng CSS/SwiftUI trong app | Remotion (React → frame → MP4), chạy trên ảnh chụp thật |
| B. Prototype **tất cả nhóm màn hình** cho iPad/browser, nối được với nhau | HTML tĩnh, nhiều khung, link qua lại, mở bằng `file://` hoặc một static server | không cần repo nào trong video — HTML/CSS + `prototype` + `impeccable` |

Video giải quyết A. B vẫn là HTML như các prototype trong `archive/`. Đừng trộn: một MP4 không phải prototype bấm được,
một prototype HTML không phải bằng chứng về nhịp motion.

## 10 repo — quyết định

| # | Repo | Nó là gì (đã đọc README) | Cho banbe | Quyết định |
| --- | --- | --- | --- | --- |
| 1 | [lemomo-ai/lemo-opuscar](https://github.com/lemomo-ai/lemo-opuscar) | Thư viện 99 style phim làm bằng code + bộ `core/` riêng (playwright-core + three, `core/render/*.mjs`, ffmpeg, TTS, nhạc, phụ đề, loudnorm −14 LUFS) | Pipeline phim có tiếng; nặng (Node 20+, Chrome, ffmpeg, Python 3.11+), 30–60 phút/phim; style library không liên quan ngôn ngữ hình ảnh giấy/mực của banbe | **Không cài.** Đọc `DIRECTOR.md` + `TECHNIQUE.md` như tài liệu dạy kể chuyện và `readcheck` (chữ trên màn hình phải đủ lâu để đọc) — đã ghi vào `rig/README.md` |
| 2 | [mrdoob/three.js](https://github.com/mrdoob/three.js) | WebGL engine | Chỉ hữu ích nếu có một khoảnh khắc 3D thật; banbe là paper/editorial, không có 3D | **Không cài** |
| 3 | [patch-gg/pixelfx](https://github.com/patch-gg/pixelfx) | 244 hiệu ứng pixel-art bằng code, MIT | Pixel-art game VFX, không có chỗ trong banbe | **Không cài** |
| 4 | [ahujasid/mcp-for-blender](https://github.com/ahujasid/mcp-for-blender) | MCP điều khiển Blender | Cần Blender + asset 3D tự dựng = đúng thứ "ảnh bịa" cần tránh | **Không cài** |
| 5 | [yihui-dev/awesome-opus5-5-videos](https://github.com/yihui-dev/awesome-opus5-5-videos) · [joeseesun/opus-video-prompts](https://github.com/joeseesun/opus-video-prompts) | Kho prompt video (703 mục / 418 bản remake) | Chỉ để học *từ vựng* chuyển động (push-in, match cut, parallax); prompt sinh video = rủi ro bịa hình | **Tham khảo, không cài** |
| 6 | [JohnHeibel/ClaudeAnimationBase](https://github.com/JohnHeibel/ClaudeAnimationBase) | Starter p5.js + p5.brush, nhân vật Clawd, `ANIMATION_GUIDE.md` 461 dòng, `render.mjs` | Hoạt hình vẽ tay (nét "boiling" 12 fps) — sai chất liệu; nhưng **quy trình** đúng: storyboard → từng shot → contact sheet tự soi → render | **Không cài.** Quy trình đã chép vào `rig/README.md` |
| 7 | [pmndrs/react-three-rapier](https://github.com/pmndrs/react-three-rapier) | Physics cho react-three-fiber | Không có vật lý nào trong banbe | **Không cài** |
| 8 | [pmndrs/react-postprocessing](https://github.com/pmndrs/react-postprocessing) | Bloom/DOF/effect composer | Có thể làm "cinematic" giả tạo; nặng và không kiểm chứng được trên Safari 16.2 trong lúc prototype | **Không cài** (chỉ mở lại nếu một shot cần DOF thật) |
| 9 | [librosa/librosa](https://github.com/librosa/librosa) | Phân tích âm thanh (beat, onset) | Onboarding không có nhạc nền; beat-sync không có gì để sync | **Không cài** |
| 10 | [Vincentwei1021/video-shotcraft](https://github.com/Vincentwei1021/video-shotcraft) | Skill cho agent: 124 thẻ "shot recipe" + 150 motion preview, **chụp trang thật**, dựng bằng **Remotion**, render MP4, Motion Workbench, Apache-2.0 (audio riêng từng file; Remotion license riêng) | Đúng bài nhất: ảnh thật + React + render ra MP4 + soi từng frame | **Cài phương pháp**: rig Remotion riêng trong `rig/`, không bê nguyên 124 thẻ (file count + văn phạm quảng cáo sản phẩm). Session có thể `git clone` full repo nếu cần thư viện shot |

Đọc thêm: [agentpedia roundup 10 repo](https://agentpedia.codes/zh/blog/claude-motion-graphics-github-repos),
[benjoox/awesome-ai-motion-graphics](https://github.com/benjoox/awesome-ai-motion-graphics).

## Đã cài: `docs/prototypes/rig/`

Remotion 4 (`remotion`, `@remotion/cli`, `react`, `react-dom` — 242 package, `npm install` exit 0, 12 s) trong một
workspace **riêng**, không thêm gì vào `package.json` của app. `node_modules/` và `out/` đã gitignore.

- 2 composition: `OnboardingWide` 1440×900 và `OnboardingPhone` 390×844, cùng một component.
- Ảnh đầu vào là **ảnh chụp thật** trong `rig/public/screens/`. Shot chưa có ảnh thì vẽ ô "capture: …" ghi rõ cần chụp
  gì — **không bao giờ** vẽ một màn hình giả để lấp chỗ.
- License: Remotion miễn phí cho cá nhân và công ty ≤ 3 người; banbe là dự án một người, nhưng nếu sau này có team thì
  phải mua Company License ([remotion.pro](https://www.remotion.pro/license)). Ghi lại đây để không quên.

## Nguồn miễn phí thay Mobbin (dùng cho research)

Mobbin là thư viện màn hình thật của app thật. Bản miễn phí bị giới hạn; đây là các chỗ **miễn phí hoặc có free tier
dùng được**, kiểm ngày 2026-11-27:

| Nguồn | Miễn phí cái gì | Dùng để |
| --- | --- | --- |
| [Kombai Gallery](https://kombai.com/gallery) | 20.000+ thiết kế UI, xem live, không cần tài khoản | Xem pattern web (hero, nav, dashboard, form) |
| [Pixlpin](https://pixlpin.com) | 58.000+ màn hình thật từ 156 app + 15.000 flow | Onboarding/permission/settings của app thật |
| [Banani References](https://www.banani.co/references) | 100+ màn hình & flow app nổi tiếng, không cần đăng ký | So sánh nhanh một flow cụ thể |
| [Refero](https://refero.design) | Free tier ~3% thư viện | Khi cần tìm theo từ khoá |
| [Appshots](https://appshots.design) | Free plan, 120.000+ màn hình | Màn hình app iOS |
| [before.click](https://before.click) | Gallery App Store screenshot + onboarding, miễn phí | Ảnh onboarding đứng riêng (như ảnh mẫu của owner) |
| [Page Flows](https://pageflows.com) | 3 ngày trial có ghi hình flow | Xem *chuyển động* giữa các bước |
| [Collect UI](https://collectui.com) | Gallery pattern miễn phí | Chi tiết nhỏ (empty state, stepper) |
| [Land-book](https://land-book.com) · [Awwwards](https://www.awwwards.com) | Browse miễn phí | Bố cục màn hình lớn |
| Mobbin | Free tier giới hạn | Chỉ khi các chỗ trên không có |

**Luật ảnh**: nguồn ngoài chỉ để học *bố cục/nhịp*. Pixel của banbe phải là ảnh thật của banbe — chụp production
(Playwright ở 390×844, 834×1194, 1440×900 với dữ liệu thật) hoặc simulator iOS. Stock (Unsplash/Pexels) chỉ được dùng
làm *texture nền có ghi chú rõ là stock*, không bao giờ làm UI trong app.

## Việc không làm ở đây

Nghiên cứu sâu + dựng prototype là việc của từng ngày (`docs/prototypes/missions/`), chạy trong một phiên Freebuff
mới. Trang này chỉ trả lời "cái nào dùng được, cái nào đã cài".
