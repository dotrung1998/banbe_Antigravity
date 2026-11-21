# Một màn trong golden set

Mỗi file mô tả **một** màn: route, dữ liệu, điều phải đúng, điều đã từng sai.

```markdown
---
screen: event
route: /event/<key>
data: event công khai còn vé
shots: [event-390-light.png, event-1440-light.png]
updated: YYYY-MM-DD
---

## Điều phải đúng
- Giá chỉ xuất hiện ở stub.
- Stepper không vượt số vé còn lại.
- Còn N vé khớp sau reload.

## Đã từng sai
- (ngày) mô tả + note/file liên quan.
```
