# decisions/ — câu trả lời của owner, do bảng Glance ghi

Mỗi ngày một file `day-0N.json`, ghi bởi `ops-data` (banbe-ops) khi owner bấm một lựa chọn trên
`http://macbook-air-von-the.tail8ab714.ts.net:8080/prototype`. Mỗi ngày có **5 câu — một câu cho mỗi cụm**
(`onboarding`, `discover`, `event`, `me`, `host`); key trong `answers` là `id` của câu hỏi, và câu nào thuộc cụm nào thì
xem `cluster` trong `questions/day-0N.json`.

```json
{
  "day": 1,
  "updated_at": "2026-11-28T14:05:11+07:00",
  "answers": {
    "dis-base": { "choice": "code", "choice_label": "Từ code hiện tại", "note": "", "at": "2026-11-28T14:05:11+07:00" }
  },
  "note": { "text": "thêm một câu về consent", "at": "2026-11-28T14:07:02+07:00" }
}
```

- **Không sửa tay.** Cần đổi thì bấm lại trên bảng; owner có thể thêm ghi chú ngay dưới câu hỏi.
- Mỗi lần ghi, `ops-data` cũng ghi đè note trong vault: `docs/second-brain/raw/inbox/prototype-day-0N.md`. Đó là thứ
  agent đọc đầu ngày (và là thứ Quartz hiện trong tab Notes).
- Câu chưa trả lời thì không có key. Mission phải đọc file này **trước** khi vẽ, và phải nói rõ câu nào còn trống.
