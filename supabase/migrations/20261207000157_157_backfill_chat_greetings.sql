-- Bilingual opening message + backfill.
--
-- The opening message must follow the viewer's app language, so it is stored in
-- two columns: chat_greeting (Vietnamese, added in 156) and chat_greeting_en.
-- Clients show the one matching the app language, falling back to the other if
-- only one is set, and to a built-in localized default when both are empty.
--
-- Backfill: every existing event without a greeting gets one of five varied
-- pairs (picked per event, so hosts don't all open with "Mình là <name>"; only
-- one variant uses the organizer's name). All data at this point is test data,
-- so this is applied to every host. Hosts can edit/clear it per event.
-- Events that already have a greeting are untouched; re-running is harmless.

ALTER TABLE public.events ADD COLUMN IF NOT EXISTS chat_greeting_en text;
ALTER TABLE public.events DROP CONSTRAINT IF EXISTS events_chat_greeting_en_len;
ALTER TABLE public.events
  ADD CONSTRAINT events_chat_greeting_en_len CHECK (chat_greeting_en IS NULL OR char_length(chat_greeting_en) <= 500);

WITH pick AS (
  SELECT e.id,
         abs(hashtext(e.id::text)) % 5 AS k,
         coalesce(nullif(btrim(o.name), ''), 'host') AS nm
  FROM public.events e
  LEFT JOIN public.organizers o ON o.id = e.organizer_id
  WHERE (e.chat_greeting IS NULL OR btrim(e.chat_greeting) = '')
    AND (e.chat_greeting_en IS NULL OR btrim(e.chat_greeting_en) = '')
)
UPDATE public.events e
SET chat_greeting = left(CASE p.k
      WHEN 0 THEN 'Chào bạn, mình là ' || p.nm || '. Cứ nhắn mình thoải mái nhé!'
      WHEN 1 THEN 'Xin chào! Bạn có câu hỏi gì về sự kiện này không? Cứ hỏi nhé.'
      WHEN 2 THEN 'Cảm ơn bạn đã quan tâm đến sự kiện. Cần biết thêm gì, nhắn mình nhé!'
      WHEN 3 THEN 'Chào bạn! Mình sẵn sàng giải đáp mọi thắc mắc trước giờ diễn ra.'
      ELSE 'Hẹn gặp bạn ở sự kiện! Cần hỗ trợ gì cứ nhắn ở đây.' END, 500),
    chat_greeting_en = left(CASE p.k
      WHEN 0 THEN 'Hi, this is ' || p.nm || '. Feel free to message me anytime!'
      WHEN 1 THEN 'Hello! Got a question about this event? Just ask.'
      WHEN 2 THEN 'Thanks for your interest in the event. Message me if you need to know anything!'
      WHEN 3 THEN 'Hi there! Happy to answer any questions before the event.'
      ELSE 'Looking forward to seeing you! Message here if you need anything.' END, 500)
FROM pick p
WHERE e.id = p.id;
