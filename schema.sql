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
-- Superseded by pt_boards/pt_nodes/pt_edges below (the annotation *graph*
-- model) — kept here, untouched, since dropping a table isn't safely
-- idempotent and nothing currently depends on removing it.
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
-- Annotation graph: spatial canvases (Boards) holding visual elements
-- (GraphNodes — highlights, notes, ink, images, AI summaries, …) and the
-- relationships between them (GraphEdges). See
-- `lib/core/models/graph/{board,graph_node,graph_edge}.dart` for the Dart
-- shapes this mirrors, and `SyncEngine.push/pullBoards`/`Nodes`/`Edges` for
-- how rows here map to those models. `style`/`content`/`anchor` are `jsonb`
-- so new sub-fields (a new NodeContent variant, a new style knob) never
-- require a migration — only the scalar geometry columns on pt_nodes
-- (x/y/w/h/rotation/z) are broken out, since those are queried/sorted on
-- directly by a canvas viewport, not just round-tripped opaquely.
-- ─────────────────────────────────────────────────────────────
create table if not exists pt_boards (
  user_id text not null,
  id text not null,
  title text not null default '',
  book_id text null,
  is_default_for_book boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists pt_boards_user_id_idx on pt_boards (user_id);

create table if not exists pt_nodes (
  user_id text not null,
  id text not null,
  board_id text not null,
  kind text not null default 'textNote',
  x double precision not null default 0,
  y double precision not null default 0,
  w double precision not null default 0,
  h double precision not null default 0,
  rotation double precision not null default 0,
  z double precision not null default 0,
  style jsonb not null default '{}'::jsonb,
  content jsonb not null default '{}'::jsonb,
  anchor jsonb null,
  content_text text not null default '',
  badge text null,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists pt_nodes_user_board_idx on pt_nodes (user_id, board_id);

-- Tombstone column for soft-deleted nodes (annotation deletes propagate via
-- last-write-wins like any other field, rather than by removing the row).
-- Separate ALTER so re-running this file on a project created before this
-- column existed still adds it (create-table-if-not-exists won't).
alter table pt_nodes add column if not exists deleted boolean not null default false;

create table if not exists pt_edges (
  user_id text not null,
  id text not null,
  board_id text not null,
  from_node_id text not null,
  to_node_id text not null,
  kind text not null default 'arrow',
  label text null,
  style jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists pt_edges_user_board_idx on pt_edges (user_id, board_id);

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
alter table pt_boards enable row level security;
alter table pt_nodes enable row level security;
alter table pt_edges enable row level security;

drop policy if exists pt_books_anon_all on pt_books;
create policy pt_books_anon_all on pt_books
  for all using (true) with check (true);
drop policy if exists pt_collections_anon_all on pt_collections;
create policy pt_collections_anon_all on pt_collections
  for all using (true) with check (true);
drop policy if exists pt_annotations_anon_all on pt_annotations;
create policy pt_annotations_anon_all on pt_annotations
  for all using (true) with check (true);
drop policy if exists pt_boards_anon_all on pt_boards;
create policy pt_boards_anon_all on pt_boards
  for all using (true) with check (true);
drop policy if exists pt_nodes_anon_all on pt_nodes;
create policy pt_nodes_anon_all on pt_nodes
  for all using (true) with check (true);
drop policy if exists pt_edges_anon_all on pt_edges;
create policy pt_edges_anon_all on pt_edges
  for all using (true) with check (true);
