-- Wrap sync tables. Run once in the Supabase SQL editor.
-- Each row belongs to one user; row-level security means people only ever see their own.

create table if not exists public.projects (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null default '',
  client_name text not null default '',
  is_wrapped  boolean not null default false,
  created_at  timestamptz not null default now(),
  deleted     boolean not null default false,
  updated_at  timestamptz not null default now()
);

create table if not exists public.shots (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  project_id  uuid not null,
  title       text not null default '',
  is_done     boolean not null default false,
  sort_order  integer not null default 0,
  outfit      text not null default '',
  location    text not null default '',
  notes       text not null default '',
  deleted     boolean not null default false,
  updated_at  timestamptz not null default now()
);

create table if not exists public.workspace_items (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  project_id  uuid not null,
  kind        text not null default 'file',
  name        text not null default '',
  location    text not null default '',
  sort_order  integer not null default 0,
  deleted     boolean not null default false,
  updated_at  timestamptz not null default now()
);

-- The server stamps every change, so each Mac can ask "what changed since…".
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists touch_projects on public.projects;
create trigger touch_projects before insert or update on public.projects
  for each row execute function public.touch_updated_at();
drop trigger if exists touch_shots on public.shots;
create trigger touch_shots before insert or update on public.shots
  for each row execute function public.touch_updated_at();
drop trigger if exists touch_workspace_items on public.workspace_items;
create trigger touch_workspace_items before insert or update on public.workspace_items
  for each row execute function public.touch_updated_at();

create index if not exists projects_user_updated on public.projects (user_id, updated_at);
create index if not exists shots_user_updated on public.shots (user_id, updated_at);
create index if not exists workspace_items_user_updated on public.workspace_items (user_id, updated_at);

-- Row-level security: only your own rows.
alter table public.projects enable row level security;
alter table public.shots enable row level security;
alter table public.workspace_items enable row level security;

drop policy if exists "Own projects" on public.projects;
create policy "Own projects" on public.projects for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Own shots" on public.shots;
create policy "Own shots" on public.shots for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Own workspace items" on public.workspace_items;
create policy "Own workspace items" on public.workspace_items for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
