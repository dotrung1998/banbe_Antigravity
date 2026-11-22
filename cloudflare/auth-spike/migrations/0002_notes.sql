-- A deliberately tiny tenant-owned table. D1 has no RLS, so every read and
-- write below is scoped with session.user.id in src/worker.js. The index is
-- on the column every tenant query filters by.
create table "notes" (
  "id" text not null primary key,
  "user_id" text not null references "user" ("id") on delete cascade,
  "body" text not null,
  "created_at" text not null default (datetime('now'))
);

create index "notes_user_id_idx" on "notes" ("user_id");
