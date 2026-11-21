---
id: 001
title: Home band
added: 2026-11-22
status: alive
refs: [.claude/notes/94-home-band-and-web-top-bands.md, .claude/notes/95-home-band-folds-on-scroll.md, .claude/notes/96-band-pick-returns-to-events.md]
---

# 001 — Home band

**Luật.** Không có JS gắn với scroll để đổi chiều cao header.

**Vì sao.** Chiều cao đổi theo scroll làm tab bị cắt, back không trở lại đúng chỗ, và mỗi lần mở Home lại thấy một header khác. Một app bar tĩnh rẻ hơn, dễ kiểm hơn và không giật trên máy yếu.

**Phản ví dụ.** Band morph theo `scrollY` (note 93): tab bị cắt ở 320, scroll-linked JS phải tính lại sau mỗi lần đổi view.

**Kiểm.** 320 và 390, light + dark; cuộn xuống rồi chọn lại đúng tab đang mở → feed phải về đầu danh sách.
