---
id: 006
title: Nền tảng
added: 2026-11-22
status: alive
refs: [.claude/notes/90-modern-web-guidance-pass.md]
---

# 006 — Nền tảng

**Luật.** Tính năng mới phải chạy trên engine cũ nhất mà app đang phục vụ, hoặc có fallback thật.

**Vì sao.** Sàn là Safari 16.2 / iOS 16.2 (vì `color-mix()`). Thứ cần 17.4 không phải "mới hơn", nó là thứ một phần người dùng không thấy.

**Phản ví dụ.** Dùng `Promise.withResolvers` hoặc popover API không fallback; animation không tắt được bằng Reduce Motion.

**Kiểm.** `npx modern-web-guidance@latest legacy-scan src --json`; mọi animation tắt được với Reduce Motion; `color-mix()` là mức thấp nhất được dùng.
