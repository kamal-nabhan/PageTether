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
-- (see `AuthNotifier.syncUserId` in the app) — NOT Supabase Auth. Because a
-- BYOD project is presumed private to one person/household (you created it,
-- you hold the only anon key), Row Level Security is left OFF here rather
-- than modeled around `auth.uid()`, which would require signing in to
-- *Supabase* itself (a separate concern from PageTether's Google sign-in)
-- for no real benefit in a single-tenant database. If you'd rather turn RLS
-- on anyway (e.g. you're exposing this project's anon key more broadly than
-- "just this app on my own devices"), the permissive policy block at the
-- bottom does that safely — every row is still readable/writable by anyone
-- holding the anon key either way, so enabling it only changes *how* that's
-- expressed, not what's actually allowed.

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
-- Optional: Row Level Security.
--
-- Left disabled by default (see the note at the top of this file). If you
-- want it on anyway, uncomment the block below — it's a *permissive* policy
-- (every request using the anon key can read/write every row), so it
-- doesn't require Supabase Auth or change what the app can do; it just
-- makes the "anyone with the anon key" trust boundary explicit at the
-- database level instead of implicit.
-- ─────────────────────────────────────────────────────────────
-- alter table pt_books enable row level security;
-- alter table pt_collections enable row level security;
-- alter table pt_annotations enable row level security;
--
-- drop policy if exists pt_books_anon_all on pt_books;
-- create policy pt_books_anon_all on pt_books
--   for all using (true) with check (true);
-- drop policy if exists pt_collections_anon_all on pt_collections;
-- create policy pt_collections_anon_all on pt_collections
--   for all using (true) with check (true);
-- drop policy if exists pt_annotations_anon_all on pt_annotations;
-- create policy pt_annotations_anon_all on pt_annotations
--   for all using (true) with check (true);
