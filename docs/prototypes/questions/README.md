# questions/day-0N.json — schema

Mỗi ngày một file, **5 câu — mỗi cụm một câu** (`onboarding`, `discover`, `event`, `me`, `host`; ngày 8 là `review`).
Session của ngày N ghi file cho ngày N+1 trước khi kết thúc; file của ngày đã qua thì không sửa (câu trả lời trong
`decisions/` trỏ tới `id`, sửa `id` là mất dấu).

```json
{
  "day": 3,
  "title": "Ngày 3 · Dữ liệu thật — trạng thái xấu hiện thế nào?",
  "helper": "Mỗi cụm một câu. Bấm là ghi vào decisions/day-03.json và vault.",
  "questions": [
    {
      "id": "evt-state",
      "cluster": "event",
      "cluster_title": "Cụm 3 · Event Detail + Reserve/Hold + Ticket",
      "q": "Hết vé / huỷ / giữ chỗ hết hạn?",
      "helper": "Ba trạng thái này từng trông giống nhau — đây là chỗ sinh ra tranh chấp.",
      "options": [
        { "id": "three-block", "label": "Ba khối riêng, cùng chỗ", "detail": "Không ai nhầm vé còn với vé hết" },
        { "id": "banner", "label": "Băng cảnh báo trên cùng", "detail": "Thấy ngay, nhưng dễ trôi khi cuộn" }
      ]
    }
  ]
}
```

Luật:

- `cluster` phải khớp `id` trong `docs/prototypes/missions/plan.json`; `cluster_title` là nhãn hiện trên bảng.
- `id` câu hỏi và `id` lựa chọn: chữ thường, không dấu, `[a-z0-9-]`, ổn định.
- 2–4 lựa chọn. Lựa chọn **đầu tiên** là cái session đề xuất, và phải nói rõ đánh đổi trong `detail`.
- `detail` ≤ 90 ký tự (bảng Glance chỉ có một dòng).
- Không câu nào dạng "bạn thích A hay B?" mà không nêu hậu quả; owner đang chọn *quyết định*, không chọn *cảm giác*.
- `helper` của file: một câu, nói chuyện gì xảy ra sau khi bấm (ghi vào vault ở đâu).
- Câu của một cụm phải trả lời được **trước** khi session của cụm đó dựng: nó chốt hướng, không chốt chi tiết pixel.
