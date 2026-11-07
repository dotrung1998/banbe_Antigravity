-- Remove the 210 test seed (throwaway stack only) so 10_seed.sql can run again.
DELETE FROM public.notifications WHERE recipient_id IN (SELECT id FROM auth.users WHERE email LIKE 'pj.%@example.com');
DELETE FROM public.events WHERE id LIKE 'pj\_%';
DELETE FROM public.organizers WHERE id = 'org_pj';
DELETE FROM auth.users WHERE email LIKE 'pj.%@example.com';
UPDATE public.app_feature_flags SET enabled = false
 WHERE key IN ('event_project_hub', 'project_qr_invite', 'project_delegate_checkin', 'project_delegate_payments', 'project_delegate_refunds');
