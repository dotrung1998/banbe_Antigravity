-- Rollback for 198. NOT a migration. Translation rows are harmless to keep; remove them only if needed.
DROP FUNCTION IF EXISTS public.get_host_confirmation_time(text);
DELETE FROM public.notification_i18n_body_rules WHERE pos BETWEEN 200 AND 204;
DELETE FROM public.notification_i18n_titles WHERE vi IN (
  'Nhắc duyệt sự kiện', 'Đã mở trò chuyện tạm thời với khách', 'Vé đã được trả lại', 'Thông báo từ host',
  'Cần bỏ phiếu: gỡ quyền quản trị', 'Cần bỏ phiếu: gỡ quyền quản lý đội ngũ',
  'Cuộc bỏ phiếu đã được thông qua', 'Cuộc bỏ phiếu không được thông qua');
