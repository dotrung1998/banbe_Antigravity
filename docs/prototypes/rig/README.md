# motion rig — ảnh thật, chuyển động bằng code

Một workspace Remotion **riêng** (không thêm gì vào `package.json` của app). Nó chỉ làm một việc: biến ảnh chụp thật
của banbe thành một đoạn motion 9–15 giây để chốt **nhịp và hướng chuyển** trước khi dựng lại bằng CSS/SwiftUI.

```bash
cd docs/prototypes/rig
npm install                 # đã chạy 2026-11-27: 242 package
npm run studio              # xem/sửa timeline trong browser
npm run still               # 1 frame PNG → out/frame.png (kiểm nhanh)
npm run render              # MP4 → out/onboarding.mp4
```

Ảnh đầu vào: `public/screens/01-home.png`, `02-event.png`, `03-ticket.png` — khai báo trong `src/shots.js`.
Chưa có ảnh thì rig vẽ ô "Capture: …" với đúng hướng dẫn chụp. **Không có ảnh giả, không có màn hình bịa.**

## Cách làm (mượn từ 3 repo trong video, không bê code)

| Mượn từ | Cái gì | Ở đâu trong rig |
| --- | --- | --- |
| [ClaudeAnimationBase](https://github.com/JohnHeibel/ClaudeAnimationBase) (MIT) | Storyboard trước → dựng từng shot → render contact sheet để **tự soi** → mới render cả bài | `src/shots.js` là storyboard; `npm run still` là contact sheet |
| [video-shotcraft](https://github.com/Vincentwei1021/video-shotcraft) (Apache-2.0) | Chụp trang thật, chọn "shot recipe" (push-in, pan, settle), dựng bằng Remotion, soi từng frame | `src/motion.js`: `push`, `panLeft`, `settle`, `captionRise` |
| [lemo-opuscar](https://github.com/lemomo-ai/lemo-opuscar) | `readcheck`: chữ trên màn hình phải ở đủ lâu để đọc | Luật: caption giữ ≥ 1.5 s; đừng đặt chữ lên ảnh đang chuyển |

Không dùng: p5.brush/pixel-art (sai chất liệu), three.js/rapier/postprocessing (không có 3D), librosa (không có nhạc),
Blender MCP (asset 3D = ảnh bịa). Lý do đầy đủ: `../RESEARCH-video-repos.md`.

## Luật

1. **Ảnh thật.** Chụp production hoặc simulator, dữ liệu thật; ghi `capture.md` (URL, event id, ngày, khung).
2. **Một ý mỗi shot.** Shot có hai ý thì tách.
3. **Caption dưới, không đè lên UI.** Người xem phải đọc được màn hình, không chỉ đọc chữ.
4. **Không hiệu ứng vì hiệu ứng.** `scale` tối đa ~1.08; đừng blur, đừng bloom.
5. **Xuất cả still.** Mỗi lần chốt, render 3 still (đầu/giữa/cuối) để so sánh và để dán vào notes.md.

## License

Remotion miễn phí cho cá nhân và công ty ≤ 3 người; banbe hiện là dự án một người. Nếu có team, mua Company License
([remotion.pro/license](https://www.remotion.pro/license)). `node_modules/` và `out/` đã gitignore.

## Đã kiểm / chưa kiểm

- `npm install` exit 0 (12 s, 242 package) → `remotion` 4.0.547.
- `npx remotion compositions src/index.js` → `OnboardingWide` 1440×900 và `OnboardingPhone` 390×844, 288 frame (9,6 s).
- `npx remotion still … --frame=40` → `out/frame.png`, đúng ô "Capture: home" (chưa có ảnh thật nên rig từ chối vẽ màn hình).
- **Chưa chạy** `npm run render` (MP4 đủ 288 frame) và **chưa** render với ảnh thật — ngày 1 làm việc đó.
