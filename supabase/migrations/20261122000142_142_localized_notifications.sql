-- Migration 142: in-app notifications follow the recipient's language setting.
--
-- Problem: every notification title/body is written by a SQL function, in Vietnamese,
-- and the apps display it as stored — so an English-language user saw Vietnamese
-- notifications regardless of their setting (emails already follow profiles.locale).
--
-- Fix, entirely in the database so web, iOS and any future push all agree:
--   * notifications keeps the ORIGINAL text (orig_title / orig_body, always the
--     Vietnamese the writing function produced);
--   * a BEFORE INSERT trigger stores title/body in the recipient's CURRENT locale;
--   * changing profiles.locale re-localizes that user's existing notifications from the
--     originals, so switching language switches what they already have, both ways.
-- Translation is table-driven (notification_i18n_*): exact titles, ordered regex
-- rules for bodies that carry names/amounts/codes (those are captured and passed
-- through untouched), and the fixed "reason" labels the apps offer. Anything with no
-- rule — chat previews, free-text reasons — is left exactly as written; this never
-- blocks or fails an insert.
-- Additive. Does not edit any earlier migration.

CREATE TABLE IF NOT EXISTS public.notification_i18n_titles (
  vi text PRIMARY KEY,
  en text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.notification_i18n_body_rules (
  pos int PRIMARY KEY,
  vi_pattern text NOT NULL,
  en_replacement text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.notification_i18n_reasons (
  vi text PRIMARY KEY,
  en text NOT NULL
);
ALTER TABLE public.notification_i18n_titles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_i18n_body_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_i18n_reasons ENABLE ROW LEVEL SECURITY;

INSERT INTO public.notification_i18n_titles (vi, en) VALUES
  ($q$Một khách đã đổi tên$q$, $q$A guest changed their name$q$),
  ($q$Bạn đã được điểm danh$q$, $q$You've been checked in$q$),
  ($q$Tin nhắn mới$q$, $q$New message$q$),
  ($q$Điểm danh của bạn đã được huỷ$q$, $q$Your check-in was reversed$q$),
  ($q$Vé của bạn đã bị huỷ$q$, $q$Your ticket was cancelled$q$),
  ($q$Một người bạn vừa tham gia banbe$q$, $q$A friend just joined banbe$q$),
  ($q$Khách báo đã chuyển khoản$q$, $q$Guest reported a transfer$q$),
  ($q$Đã nhận thanh toán$q$, $q$Payment received$q$),
  ($q$Có người tham gia mới$q$, $q$New attendee$q$),
  ($q$Yêu cầu đặt chỗ mới$q$, $q$New booking request$q$),
  ($q$Cần xác nhận thanh toán$q$, $q$Payment needs confirmation$q$),
  ($q$Thanh toán đang được xem xét$q$, $q$Payment under review$q$),
  ($q$Kết quả xem xét thanh toán$q$, $q$Payment review result$q$),
  ($q$Hết thời gian giữ chỗ$q$, $q$Hold expired$q$),
  ($q$Cần thêm thông tin chuyển khoản$q$, $q$More transfer details needed$q$),
  ($q$Tin nhắn mới về tranh chấp$q$, $q$New message about a dispute$q$),
  ($q$Đã xác nhận$q$, $q$Confirmed$q$),
  ($q$Đã giữ chỗ$q$, $q$Spot held$q$),
  ($q$Hoá đơn đã được cập nhật$q$, $q$Invoice updated$q$),
  ($q$Biên nhận đã được cập nhật$q$, $q$Receipt updated$q$),
  ($q$Hoá đơn đã sẵn sàng$q$, $q$Invoice ready$q$),
  ($q$Biên nhận đã sẵn sàng$q$, $q$Receipt ready$q$),
  ($q$Khách đang chờ xác nhận$q$, $q$A guest is waiting for confirmation$q$),
  ($q$Yêu cầu đặt chỗ không được nhận$q$, $q$Booking request declined$q$),
  ($q$Khách yêu cầu biên nhận$q$, $q$Guest requested a receipt$q$),
  ($q$Người tổ chức đã báo hoàn tiền$q$, $q$Organizer reported a refund$q$),
  ($q$Khách đã xác nhận nhận được hoàn tiền$q$, $q$Guest confirmed the refund$q$),
  ($q$Khách báo chưa nhận được hoàn tiền$q$, $q$Guest reported the refund hasn't arrived$q$),
  ($q$Hoàn tiền quá hạn 72 giờ$q$, $q$Refund overdue by 72 hours$q$),
  ($q$Người tổ chức đã gửi lại thông tin chuyển khoản$q$, $q$Organizer resent the transfer details$q$),
  ($q$Quá hạn hoàn tiền$q$, $q$Refund overdue$q$),
  ($q$Khiếu nại hoàn tiền quá hạn phản hồi$q$, $q$Refund dispute awaiting a response$q$),
  ($q$Sự kiện đã được duyệt$q$, $q$Event approved$q$),
  ($q$Sự kiện cần chỉnh sửa$q$, $q$Event needs changes$q$),
  ($q$Một người tổ chức bạn theo dõi đã đổi tên$q$, $q$An organizer you follow changed their name$q$),
  ($q$Lời mời tham gia Team$q$, $q$Team invitation$q$),
  ($q$Lời mời đã được chấp nhận$q$, $q$Invitation accepted$q$),
  ($q$Lời mời đã bị từ chối$q$, $q$Invitation declined$q$),
  ($q$Ghi nhận đóng góp sự kiện$q$, $q$Event contribution credit$q$),
  ($q$Bạn được mời tham dự một sự kiện riêng tư$q$, $q$You're invited to a private event$q$),
  ($q$Lời mời trở thành quản trị viên$q$, $q$Invitation to become an admin$q$),
  ($q$Lời mời quản trị đã được chấp nhận$q$, $q$Admin invitation accepted$q$),
  ($q$Lời mời quản trị đã bị từ chối$q$, $q$Admin invitation declined$q$),
  ($q$Quyền quản trị đã bị thu hồi$q$, $q$Admin access revoked$q$),
  ($q$Hoàn tiền được tự động xác nhận$q$, $q$Refund automatically confirmed$q$),
  ($q$Tranh chấp hoàn tiền đã kết thúc$q$, $q$Refund dispute closed$q$),
  ($q$Tranh chấp hoàn tiền sắp tự đóng$q$, $q$Refund dispute closing soon$q$),
  ($q$Tranh chấp hoàn tiền đã tự đóng$q$, $q$Refund dispute closed automatically$q$)
ON CONFLICT (vi) DO UPDATE SET en = EXCLUDED.en;

DELETE FROM public.notification_i18n_body_rules;
INSERT INTO public.notification_i18n_body_rules (pos, vi_pattern, en_replacement) VALUES
  (1, $q$^Một khách vừa gửi xác nhận chuyển khoản\. Kiểm tra và đánh dấu đã thanh toán\.$$q$, $q$A guest just sent a transfer confirmation. Check it and mark it as paid.$q$),
  (2, $q$^Người tổ chức xác nhận đã nhận thanh toán của bạn\. Biên nhận đã sẵn sàng trong Tài khoản\.$$q$, $q$The organizer confirmed they received your payment. Your receipt is ready in Account.$q$),
  (3, $q$^Thanh toán của bạn đã được xác nhận\. Vé và biên nhận đã sẵn sàng\.$$q$, $q$Your payment was confirmed. Your ticket and receipt are ready.$q$),
  (4, $q$^Người tổ chức chưa xác nhận được khoản chuyển khoản của bạn\. Chỗ vẫn được giữ trong lúc banbe xem xét\.$$q$, $q$The organizer couldn't confirm your transfer. Your spot is still held while banbe reviews it.$q$),
  (5, $q$^banbe đã xem xét và không xác nhận được khoản thanh toán này\. Chỗ đã được mở lại\.$$q$, $q$banbe reviewed this payment and couldn't confirm it. The spot has been released.$q$),
  (6, $q$^Chỗ của bạn đã được mở lại vì chưa nhận được xác nhận chuyển khoản\.$$q$, $q$Your spot was released because no transfer confirmation was received.$q$),
  (7, $q$^Người tổ chức chưa tìm thấy khoản chuyển khoản của bạn\. Chỗ vẫn được giữ — kiểm tra tin nhắn để biết chi tiết\.$$q$, $q$The organizer couldn't find your transfer. Your spot is still held — check your messages for details.$q$),
  (8, $q$^banbe đang xem xét khoản thanh toán của bạn\. Chỗ vẫn được giữ trong lúc chờ\.$$q$, $q$banbe is reviewing your payment. Your spot is still held meanwhile.$q$),
  (9, $q$^Bạn được mời tham gia đội ngũ tổ chức sự kiện\.$$q$, $q$You've been invited to join an organizer's team.$q$),
  (10, $q$^Bạn được ghi nhận là người tổ chức cho một sự kiện\.$$q$, $q$You've been credited as an organizer of an event.$q$),
  (11, $q$^Bạn được mời tham gia đội ngũ quản trị banbe\.$$q$, $q$You've been invited to join the banbe admin team.$q$),
  (12, $q$^Bạn không còn là quản trị viên của banbe\.$$q$, $q$You're no longer a banbe admin.$q$),
  (13, $q$^Người tổ chức vừa tải lên hoá đơn của bạn\.$$q$, $q$The organizer just uploaded your invoice.$q$),
  (14, $q$^Người tổ chức vừa tải lên biên nhận của bạn\.$$q$, $q$The organizer just uploaded your receipt.$q$),
  (15, $q$^Người tổ chức đã tải lên bản mới\. Lý do: $q$, $q$The organizer uploaded a new version. Reason: $q$),
  (16, $q$\. Liên hệ (.*) nếu bạn cần bản cũ trước khi bị xoá\.$$q$, $q$. Contact \1 if you need the old version before it is deleted.$q$),
  (17, $q$^Một khách đã báo chuyển khoản (.*)₫ ▪︎ mã (.*)\. Kiểm tra và xác nhận\.$$q$, $q$A guest reported a transfer of \1₫ ▪︎ code \2. Check and confirm.$q$),
  (18, $q$^(.*) đã đặt ([0-9]+) chỗ cho (.*) ▪︎ chờ xác nhận thanh toán\.$$q$, $q$\1 booked \2 seat(s) for \3 ▪︎ awaiting payment confirmation.$q$),
  (19, $q$^(.*) đã đặt ([0-9]+) chỗ cho (.*) ▪︎ mã (.*)\.$$q$, $q$\1 booked \2 seat(s) for \3 ▪︎ code \4.$q$),
  (20, $q$^(.*) đã đặt ([0-9]+) chỗ cho (.*)\.$$q$, $q$\1 booked \2 seat(s) for \3.$q$),
  (21, $q$^Bạn đã tham gia (.*)\. Vé đã sẵn sàng\.$$q$, $q$You've joined \1. Your ticket is ready.$q$),
  (22, $q$^Chỗ của bạn cho (.*) đang được giữ trong ([0-9]+) phút ▪︎ mã (.*)\. Chuyển khoản và báo lại trước khi hết giờ\.$$q$, $q$Your spot for \1 is held for \2 minutes ▪︎ code \3. Transfer the payment and report it before time runs out.$q$),
  (23, $q$^(.*) nhắc bạn xác nhận khoản thanh toán ▪︎ mã (.*)\.$$q$, $q$\1 reminded you to confirm their payment ▪︎ code \2.$q$),
  (24, $q$^(.*) đã từ chối yêu cầu đặt chỗ của bạn\.$q$, $q$\1 declined your booking request.$q$),
  (25, $q$^(.*) đang chờ biên nhận cho khoản đã thanh toán ▪︎ mã (.*)\.$$q$, $q$\1 is waiting for a receipt for the payment ▪︎ code \2.$q$),
  (26, $q$^(.*) báo đã hoàn (.*)₫ cho bạn\.$$q$, $q$\1 reported refunding \2₫ to you.$q$),
  (27, $q$^Khách xác nhận đã nhận (.*)₫ cho (.*)\.$$q$, $q$The guest confirmed receiving \1₫ for \2.$q$),
  (28, $q$^Khách báo chưa nhận được (.*)₫ cho (.*)\.$q$, $q$The guest reported not receiving \1₫ for \2.$q$),
  (29, $q$^Khoản hoàn (.*)₫ cho (.*) vẫn chưa được xử lý sau 72 giờ\.$$q$, $q$The \1₫ refund for \2 is still unprocessed after 72 hours.$q$),
  (30, $q$^(.*) đã gửi lại thông tin chuyển khoản cho khoản hoàn tiền của bạn\.$$q$, $q$\1 resent the transfer details for your refund.$q$),
  (31, $q$^Khoản hoàn (.*)₫ cho (.*) đã quá hạn\.$$q$, $q$The \1₫ refund for \2 is overdue.$q$),
  (32, $q$^Khiếu nại hoàn tiền cho (.*) đã quá 48 giờ chưa được phản hồi\.$$q$, $q$The refund dispute for \1 has gone 48 hours without a response.$q$),
  (33, $q$^Sự kiện \"(.*)\" đã được banbe duyệt và hiện đang hiển thị công khai\.$$q$, $q$Your event "\1" was approved by banbe and is now publicly visible.$q$),
  (34, $q$^Sự kiện \"(.*)\" chưa được duyệt: $q$, $q$Your event "\1" wasn't approved: $q$),
  (35, $q$^(.*) đã tham gia đội ngũ của bạn\.$$q$, $q$\1 joined your team.$q$),
  (36, $q$^(.*) đã từ chối lời mời tham gia đội ngũ\.$$q$, $q$\1 declined the invitation to join your team.$q$),
  (37, $q$^Sau 7 ngày không có phản hồi, khoản hoàn (.*)₫ cho (.*) đã được tự động xác nhận\.$$q$, $q$After 7 days with no response, the \1₫ refund for \2 was automatically confirmed.$q$),
  (38, $q$^Khoản hoàn (.*)₫ cho (.*) đã được tự động xác nhận sau 7 ngày khách không phản hồi\.$$q$, $q$The \1₫ refund for \2 was automatically confirmed after the guest didn't respond for 7 days.$q$),
  (39, $q$^Tranh chấp khoản hoàn (.*)₫ cho (.*) đã được đóng\. Bản ghi vẫn đọc được trong 7 ngày\.$$q$, $q$The dispute over the \1₫ refund for \2 was closed. The record stays readable for 7 days.$q$),
  (40, $q$^Tranh chấp khoản hoàn cho (.*) sẽ tự đóng sau 24 giờ nếu không có phản hồi\. Khoản hoàn không thay đổi\.$$q$, $q$The refund dispute for \1 will close automatically in 24 hours without a response. The refund is unchanged.$q$),
  (41, $q$^Tranh chấp khoản hoàn cho (.*) đã tự đóng sau 7 ngày\. Bản ghi vẫn đọc được trong 7 ngày\.$$q$, $q$The refund dispute for \1 closed automatically after 7 days. The record stays readable for 7 days.$q$),
  (42, $q$^(.*) đã đổi tên thành (.*)\.$$q$, $q$\1 changed their name to \2.$q$),
  (43, $q$^(.*) vừa xác nhận bạn đã có mặt\.$$q$, $q$\1 has confirmed you're here.$q$),
  (44, $q$^(.*) vừa huỷ điểm danh của bạn\.$q$, $q$\1 reversed your check-in.$q$),
  (45, $q$^(.*) đã huỷ vé của bạn\.$q$, $q$\1 cancelled your ticket.$q$),
  (46, $q$^(.*) vừa tham gia banbe qua lời mời của bạn\.$$q$, $q$\1 just joined banbe through your invite.$q$),
  (47, $q$ Khoản bạn đã thanh toán sẽ được hoàn lại\.$q$, $q$ The amount you paid will be refunded.$q$),
  (48, $q$ Lý do: $q$, $q$ Reason: $q$),
  (49, $q$^Một khách $q$, $q$A guest $q$),
  (50, $q$^Một người tham gia $q$, $q$An attendee $q$),
  (51, $q$^Một người bạn bạn đã mời $q$, $q$A friend you invited $q$);

INSERT INTO public.notification_i18n_reasons (vi, en) VALUES
  ($q$Nhầm người$q$, $q$Wrong person$q$),
  ($q$Bấm nhầm$q$, $q$Tapped by mistake$q$),
  ($q$Khách chưa thực sự có mặt$q$, $q$Guest hasn't actually arrived$q$),
  ($q$Khác$q$, $q$Other$q$),
  ($q$Sự kiện đổi lịch hoặc huỷ$q$, $q$Event rescheduled or cancelled$q$),
  ($q$Không thanh toán đúng hạn$q$, $q$Payment not completed in time$q$),
  ($q$Vi phạm quy định$q$, $q$Policy violation$q$),
  ($q$Hết chỗ thật sự$q$, $q$Actually out of seats$q$),
  ($q$Không khớp với sao kê$q$, $q$Doesn't match the statement$q$),
  ($q$Nghi ngờ gian lận$q$, $q$Suspected fraud$q$),
  ($q$Sự kiện bị huỷ do hoàn cảnh bất khả kháng$q$, $q$Cancelled due to unforeseen circumstances$q$),
  ($q$Sự kiện bị huỷ vì địa điểm không còn khả dụng$q$, $q$Cancelled because the venue is no longer available$q$),
  ($q$Sự kiện bị huỷ vì chưa đủ số lượng đăng ký$q$, $q$Cancelled because there were not enough sign-ups$q$),
  ($q$Sự kiện bị huỷ vì lý do an toàn hoặc thời tiết$q$, $q$Cancelled for safety or weather reasons$q$)
ON CONFLICT (vi) DO UPDATE SET en = EXCLUDED.en;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS orig_title text,
  ADD COLUMN IF NOT EXISTS orig_body text;

-- Pure function: original (Vietnamese) text in, text in the requested locale out.
CREATE OR REPLACE FUNCTION public.localize_notification_text(p_title text, p_body text, p_locale text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_title text := p_title;
  v_body text := p_body;
  r record;
  v_next text;
BEGIN
  IF p_locale = 'en' THEN
    SELECT en INTO v_next FROM notification_i18n_titles WHERE vi = p_title;
    IF v_next IS NOT NULL THEN v_title := v_next; END IF;

    FOR r IN SELECT vi_pattern, en_replacement FROM notification_i18n_body_rules ORDER BY pos LOOP
      v_body := regexp_replace(v_body, r.vi_pattern, r.en_replacement);
    END LOOP;

    -- Fixed reason labels the apps offer ("... Reason: Wrong person").
    FOR r IN SELECT vi, en FROM notification_i18n_reasons LOOP
      IF right(v_body, length(r.vi) + 2) = ': ' || r.vi THEN
        v_body := left(v_body, length(v_body) - length(r.vi)) || r.en;
      END IF;
    END LOOP;
  ELSE
    -- Vietnamese is the source language. The one case that needs work is a reason an
    -- English-language host picked, which was stored in English.
    FOR r IN SELECT vi, en FROM notification_i18n_reasons LOOP
      IF right(v_body, length(r.en) + 2) = ': ' || r.en AND v_body LIKE '%Lý do: %' THEN
        v_body := left(v_body, length(v_body) - length(r.en)) || r.vi;
      END IF;
    END LOOP;
  END IF;
  RETURN jsonb_build_object('title', v_title, 'body', v_body);
EXCEPTION WHEN OTHERS THEN
  -- Never let a translation problem lose or block a notification.
  RETURN jsonb_build_object('title', p_title, 'body', p_body);
END;
$$;

CREATE OR REPLACE FUNCTION public.notifications_localize_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_locale text;
  v_out jsonb;
BEGIN
  NEW.orig_title := COALESCE(NEW.orig_title, NEW.title);
  NEW.orig_body := COALESCE(NEW.orig_body, NEW.body);
  SELECT locale::text INTO v_locale FROM profiles WHERE id = NEW.recipient_id;
  IF v_locale = 'en' THEN
    v_out := localize_notification_text(NEW.orig_title, NEW.orig_body, 'en');
    NEW.title := v_out->>'title';
    NEW.body := v_out->>'body';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notifications_localize_on_insert ON public.notifications;
CREATE TRIGGER notifications_localize_on_insert
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_localize_on_insert();

-- Language switched: rewrite that user's existing notifications from the originals.
CREATE OR REPLACE FUNCTION public.profiles_relocalize_notifications()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.locale IS DISTINCT FROM OLD.locale THEN
    UPDATE notifications n
    SET title = (localize_notification_text(n.orig_title, n.orig_body, NEW.locale::text))->>'title',
        body  = (localize_notification_text(n.orig_title, n.orig_body, NEW.locale::text))->>'body'
    WHERE n.recipient_id = NEW.id AND n.orig_title IS NOT NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_relocalize_notifications ON public.profiles;
CREATE TRIGGER profiles_relocalize_notifications
  AFTER UPDATE OF locale ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_relocalize_notifications();

-- Existing rows: what is stored today is the Vietnamese original. Keep it, then
-- localize it for everyone who already uses English.
UPDATE public.notifications SET orig_title = title, orig_body = body WHERE orig_title IS NULL;

UPDATE public.notifications n
SET title = (localize_notification_text(n.orig_title, n.orig_body, 'en'))->>'title',
    body  = (localize_notification_text(n.orig_title, n.orig_body, 'en'))->>'body'
FROM public.profiles p
WHERE p.id = n.recipient_id AND p.locale::text = 'en';
