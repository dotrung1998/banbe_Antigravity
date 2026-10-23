-- 198 — Phase 1 server pieces (docs/impl/phase1-quick-wins.md).
--
-- Q2 honest waiting: get_host_confirmation_time(event) = this host's typical time from "guest reported the transfer"
--   to "host confirmed", from their last 180 days. Real data only: NULL unless at least 5 confirmations exist. Never a
--   countdown, never a promise.
-- Q6 language: English rows for notification titles/bodies added after 142 that never got one (an English-language
--   user saw Vietnamese): event review reminder (148), temporary payment chat + ticket returned (149/190), admin votes
--   (172), host announcements (166 — the title only; the body is the host's own words and stays as written).
--
-- Rollback: supabase/rollbacks/20261230000198_198_revert_quick_wins_server.sql (kept OUT of migrations/).

-- ---------------------------------------------------------------- Q2
CREATE OR REPLACE FUNCTION public.get_host_confirmation_time(p_event_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_org text;
  v_n int;
  v_median numeric;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'AUTH_REQUIRED'); END IF;
  SELECT organizer_id INTO v_org FROM events WHERE id = p_event_id;
  IF v_org IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'EVENT_NOT_FOUND'); END IF;
  SELECT count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (b.verified_at - b.proof_submitted_at)) / 60)
    INTO v_n, v_median
    FROM bookings b JOIN events e ON e.id = b.event_id
   WHERE e.organizer_id = v_org
     AND b.proof_submitted_at IS NOT NULL AND b.verified_at IS NOT NULL
     AND b.verified_at > b.proof_submitted_at
     AND b.verified_at > now() - interval '180 days';
  RETURN jsonb_build_object('success', true, 'n', v_n,
    'median_minutes', CASE WHEN v_n >= 5 THEN round(v_median) END);
END;
$$;
REVOKE ALL ON FUNCTION public.get_host_confirmation_time(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_host_confirmation_time(text) TO authenticated;

-- ---------------------------------------------------------------- Q6
INSERT INTO public.notification_i18n_titles (vi, en) VALUES
  ($q$Nhắc duyệt sự kiện$q$, $q$Event review reminder$q$),
  ($q$Đã mở trò chuyện tạm thời với khách$q$, $q$A temporary chat with the guest is open$q$),
  ($q$Vé đã được trả lại$q$, $q$Ticket returned$q$),
  ($q$Thông báo từ host$q$, $q$Message from the host$q$),
  ($q$Cần bỏ phiếu: gỡ quyền quản trị$q$, $q$Vote needed: remove admin rights$q$),
  ($q$Cần bỏ phiếu: gỡ quyền quản lý đội ngũ$q$, $q$Vote needed: remove team-management rights$q$),
  ($q$Cuộc bỏ phiếu đã được thông qua$q$, $q$The vote passed$q$),
  ($q$Cuộc bỏ phiếu không được thông qua$q$, $q$The vote did not pass$q$)
ON CONFLICT (vi) DO UPDATE SET en = EXCLUDED.en;

INSERT INTO public.notification_i18n_body_rules (pos, vi_pattern, en_replacement) VALUES
  (200, $q$^Người tổ chức nhắc bạn duyệt sự kiện "(.*)" \(lần ([0-9]+)/2\)\.$$q$, $q$The organizer reminded you to review the event "\1" (reminder \2/2).$q$),
  (201, $q$^Bạn có 2 ngày để cùng khách thống nhất khoản chuyển khoản; sau đó vé sẽ được trả lại kho\.$$q$, $q$You have 2 days to agree on the transfer with the guest; after that the ticket goes back on sale.$q$),
  (202, $q$^Hết 2 ngày mà người tổ chức chưa xác nhận khoản chuyển khoản\. Vé đã được trả lại kho\.$$q$, $q$Two days passed without the organizer confirming the transfer. The ticket went back on sale.$q$),
  (203, $q$^(.*) đã mở một cuộc bỏ phiếu\. Vào Đội Ngũ Quản Trị để bỏ phiếu\.$$q$, $q$\1 opened a vote. Go to the Admin Team to vote.$q$),
  (204, $q$^Xem chi tiết trong Đội Ngũ Quản Trị\.$$q$, $q$See the details in the Admin Team.$q$)
ON CONFLICT (pos) DO UPDATE SET vi_pattern = EXCLUDED.vi_pattern, en_replacement = EXCLUDED.en_replacement;

-- English users' existing rows of these kinds: re-localize from the originals (same as a language switch does).
UPDATE public.notifications n
   SET title = (public.localize_notification_text(n.orig_title, n.orig_body, 'en'))->>'title',
       body  = (public.localize_notification_text(n.orig_title, n.orig_body, 'en'))->>'body'
  FROM public.profiles p
 WHERE p.id = n.recipient_id AND p.locale::text = 'en' AND n.orig_title IS NOT NULL
   AND n.kind IN ('event_review_reminder', 'payment_needs_info', 'not_found_expired', 'event_announcement',
                  'admin_removal_vote', 'admin_removal_vote_result');
