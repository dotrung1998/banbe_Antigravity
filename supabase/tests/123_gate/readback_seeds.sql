-- Read-back for migration 123's three approved DOB seeds. Prints booleans only
-- (never the stored dates). Run AFTER applying the migration, as service role.
SELECT e.email,
       (d.user_id IS NOT NULL) AS has_dob,
       (d.date_of_birth = e.expected) AS matches_expected,
       d.source,
       (g.user_id IS NOT NULL) AS grandfathered,
       (u.phone_confirmed_at IS NOT NULL) AS phone_verified
FROM (VALUES
  ('dotrung1998@gmail.com',    DATE '1998-06-15'),
  ('doqanh0609@gmail.com',     DATE '2006-09-16'),
  ('banbetestadmin@gmail.com', DATE '1998-06-15')
) AS e(email, expected)
LEFT JOIN auth.users u ON lower(u.email) = lower(e.email)
LEFT JOIN public.user_private_dob d ON d.user_id = u.id
LEFT JOIN public.account_phone_grandfathered g ON g.user_id = u.id;
