-- PageTether — BYOD Supabase sync schema (Phase 4a)
--
-- This is YOUR OWN Supabase project — PageTether never sees your URL or
-- anon key; you paste them into the app's Settings screen and they're
-- stored only on your device. Run this whole file once in your project's
-- SQL Editor (Supabase Dashboard → SQL Editor → New query → paste → Run)
-- before using "Sync now". It's safe to re-run: every statement is
-- idempotent (`create table if not exists`, `create index if not exists`).
--
-- Rows are keyed by `user_id`, PageTether's stable Google-account identity
-- (see `AuthNotifier.syncUserId` in the app) — NOT Supabase Auth. This file
-- ENABLES Row Level Security on every table with a PERMISSIVE anon policy
-- (`using (true) with check (true)`) at the bottom, so it works whether or
-- not Supabase pre-enabled RLS on your tables (a table with RLS on and no
-- policy rejects every write — "new row violates row-level security policy").
-- Be clear-eyed about what this means for a BYOD project: security here is
-- "keep your anon key private" — anyone holding the anon key can read/write
-- every row, because we key on a plain `user_id` column, not `auth.uid()`.
-- That's fine for a project private to one person/household. True per-user
-- isolation would require signing in to *Supabase* itself (Supabase Auth +
-- `auth.uid()`-based policies) — a future hardening option, separate from
-- PageTether's Google sign-in.

-- ─────────────────────────────────────────────────────────────
-- Books: reading position, favorite, metadata, collection membership.
-- ─────────────────────────────────────────────────────────────
create table if not exists pt_books (
  user_id text not null,
  book_id text not null,
  title text not null default '',
  author text not null default '',
  current_page integer not null default 1,
  page_count integer not null default 0,
  is_favorite boolean not null default false,
  drive_file_id text null,
  collection_ids jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, book_id)
);

create index if not exists pt_books_user_id_idx on pt_books (user_id);

-- ─────────────────────────────────────────────────────────────
-- Collections: user-defined groupings (name + accent color).
-- ─────────────────────────────────────────────────────────────
create table if not exists pt_collections (
  user_id text not null,
  id text not null,
  name text not null default '',
  color_index integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists pt_collections_user_id_idx on pt_collections (user_id);

-- ─────────────────────────────────────────────────────────────
-- Annotations: defined now for Phase 5 (highlights/notes) — created so the
-- schema is forward-compatible, but NOT read/written by Phase 4a's sync.
-- ─────────────────────────────────────────────────────────────
create table if not exists pt_annotations (
  user_id text not null,
  id text not null,
  book_id text not null,
  page integer not null,
  type text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists pt_annotations_user_book_idx
  on pt_annotations (user_id, book_id);

-- ─────────────────────────────────────────────────────────────
-- Row Level Security: ENABLED with a permissive anon policy.
--
-- Why enable it (vs. leaving it off): Supabase enables RLS on new tables by
-- default, and a table with RLS on but NO policy rejects every write. So this
-- block guarantees the script works either way. The policy is *permissive*
-- (`using (true) with check (true)`): with only the anon key and no Supabase
-- Auth it can't isolate per user, so this makes the "anyone with the anon key
-- has full access" boundary explicit rather than restricting it. Idempotent —
-- safe to re-run.
-- ─────────────────────────────────────────────────────────────
alter table pt_books enable row level security;
alter table pt_collections enable row level security;
alter table pt_annotations enable row level security;

drop policy if exists pt_books_anon_all on pt_books;
create policy pt_books_anon_all on pt_books
  for all using (true) with check (true);
drop policy if exists pt_collections_anon_all on pt_collections;
create policy pt_collections_anon_all on pt_collections
  for all using (true) with check (true);
drop policy if exists pt_annotations_anon_all on pt_annotations;
create policy pt_annotations_anon_all on pt_annotations
  for all using (true) with check (true);
