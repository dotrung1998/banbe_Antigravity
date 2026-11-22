---
id: 002
title: Event Detail
added: 2026-11-22
status: alive
refs: [.claude/notes/70-event-detail-story-first-one-row-bar.md, .claude/notes/75-event-detail-v8-ticket-stub.md, .claude/notes/78-ticket-a-paper-ticket-whats-next.md]
---

# 002 — Event Detail

**Luật.** Một màn hình, một nơi nói giá. Không lặp lại cùng một con số ở ba kiểu chữ.

**Vì sao.** Giá, giờ, địa điểm và số vé còn lại phải trả lời được trong ba giây. Hai chỗ nói giá là hai chỗ có thể lệch nhau sau một lần refresh.

**Phản ví dụ.** "Còn 2 vé" thành "Sold out" sau refresh; giá nằm cả ở stub lẫn thanh reserve.

**Kiểm.** Stub là nơi duy nhất chứa giá; stepper không vượt số vé còn lại; `Còn N vé` khớp `seats_remaining` sau reload.
