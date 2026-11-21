# agent-os vault

Bộ nhớ của gu banbe. `docs/agent-os/index.html` mô tả vault này; đây là phần đã tồn tại thật trong repo.

| Thư mục | Nội dung | Giới hạn |
|---|---|---|
| `principles/` | Một file = một luật sống: câu luật, vì sao, phản ví dụ, nguồn | **tối đa 40 file**; thêm file 41 thì phải xoá một file |
| `golden/` | Năm màn chuẩn + 10 ảnh 390/1440 light | ảnh chuẩn, chỉ thay khi sản phẩm cố ý đổi |

## Ai đọc, ai ghi

- **Daily audit đọc** `principles/*` và `golden/README.md` trước khi chấm UI/UX.
- **Daily audit không tự sửa** principles. Mỗi lần chạy chỉ **đề xuất** thêm/sửa/xoá một luật; người duyệt quyết định.
- Chủ nhật, người duyệt xoá một luật không còn đúng. Vault không phải bảo tàng.

## Vì sao có giới hạn 40

Một luật chỉ sống khi nó còn đúng và còn được đọc. 40 là mức tối đa để một người đọc hết trong một lần ngồi; vượt qua thì agent bắt đầu trích dẫn máy móc thay vì hiểu.

## Nguồn gốc

Sáu luật đầu tiên lấy đúng từ `docs/agent-os/index.html` (mục "Sáu chỗ banbe không được trôi"), mỗi luật trỏ về note đã sinh ra nó. Sửa luật thì sửa ở đây, **không** sửa bản trong file HTML.
