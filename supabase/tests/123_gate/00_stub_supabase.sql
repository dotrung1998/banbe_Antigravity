create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema auth;
create table auth.users(id uuid primary key default gen_random_uuid(), email text, phone text, phone_confirmed_at timestamptz);
create table auth.sessions(id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade);
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true),''),'{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select nullif(auth.jwt()->>'sub','')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated;
create table public.profiles(id uuid primary key, display_name text, locale text default 'vi');
create table public.organizers(id text primary key, owner_id uuid, user_id uuid, name text);
create table public.events(id text primary key, organizer_id text, name text);
create table public.bookings(id uuid default gen_random_uuid(), event_id text, user_id uuid, status text);
create table public.follows(user_id uuid, organizer_id text);
create table public.favorites(user_id uuid, event_id text);
create table public.organizer_members(organizer_id text, user_id uuid, status text);
create table public.notifications(id serial, user_id uuid, body text);
alter table public.notifications enable row level security;
create policy own on public.notifications for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert on public.notifications to authenticated;
grant usage on all sequences in schema public to authenticated;
grant usage on schema public to anon, authenticated;
-- legacy users present BEFORE the migration
insert into auth.users(id,email) values
 ('11111111-1111-1111-1111-111111111111','dotrung1998@gmail.com'),
 ('22222222-2222-2222-2222-222222222222','DoQanh0609@gmail.com'),
 ('44444444-4444-4444-4444-444444444444','legacy.nodob@example.com');
insert into auth.sessions(id,user_id) values
 ('a0000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111'),
 ('a0000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111'),
 ('a0000000-0000-0000-0000-000000000004','44444444-4444-4444-4444-444444444444');
insert into public.notifications(user_id, body) values
 ('11111111-1111-1111-1111-111111111111','hello A'),('44444444-4444-4444-4444-444444444444','hello D');
