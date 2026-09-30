-- Wrap deliveries. Run once in the Supabase SQL editor.
-- The delivery Worker writes these rows (with the secret key); the Mac app only reads its own.

create table if not exists public.deliveries (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  project_id     uuid,
  file_name      text not null,
  size_bytes     bigint not null default 0,
  r2_key         text not null,
  upload_id      text,
  token          text not null unique,
  status         text not null default 'uploading',  -- uploading, ready, downloaded, expired, cancelled
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  downloaded_at  timestamptz,
  download_count integer not null default 0
);

create index if not exists deliveries_user_created on public.deliveries (user_id, created_at desc);
create index if not exists deliveries_status_expires on public.deliveries (status, expires_at);

alter table public.deliveries enable row level security;

drop policy if exists "Read own deliveries" on public.deliveries;
create policy "Read own deliveries" on public.deliveries for select to authenticated
  using ((select auth.uid()) = user_id);

-- Private storage for delivered files (50 MB per file on the free plan).
-- Only the delivery Worker (secret key) reads and writes here.
insert into storage.buckets (id, name, public, file_size_limit)
values ('deliveries', 'deliveries', false, 52428800)
on conflict (id) do nothing;
