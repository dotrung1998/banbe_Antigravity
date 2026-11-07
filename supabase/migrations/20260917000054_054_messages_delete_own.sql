-- .claude/notes/07-notifications.md Task B: public.messages (the ordinary
-- Chat.jsx/threads screen — distinct from dispute_messages, which
-- 05-notify-retention.md requires kept for 72h after a dispute resolves)
-- had SELECT and INSERT policies (migration 003) but no UPDATE/DELETE at
-- all. No retention requirement is documented for this table anywhere in
-- 05-notify-retention.md, so a real, permanent delete is fine — scoped to
-- the caller's own messages only. A system note (sender_id IS NULL, e.g.
-- hold_seats()'s "Đặt chỗ thành công..." message) can never match
-- `auth.uid() = sender_id` for any real user, so this can't be used to
-- erase those either.
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
CREATE POLICY "messages_delete_own" ON public.messages
  FOR DELETE TO authenticated USING (auth.uid() = sender_id);
