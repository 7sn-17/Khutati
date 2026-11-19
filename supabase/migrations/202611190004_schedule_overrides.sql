-- Manual task placements (move, reorder, pinned start time).
--
-- One row per (account, task). The template task is never modified; this row
-- only overrides where the generated schedule puts it. Deleting the row returns
-- that task to automatic scheduling.
--
-- `deleted` is a soft delete so a removal on one device also reaches the others:
-- the pull path treats a deleted row as "clear the local override". The local
-- SQLite copy remains the source of truth while offline.

create table if not exists public.user_schedule_overrides (
  user_id uuid not null references auth.users (id) on delete cascade,
  task_id text not null,
  day_number integer,
  position integer,
  start_clock text,
  deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, task_id)
);

alter table public.user_schedule_overrides enable row level security;

drop policy if exists user_schedule_overrides_owner
  on public.user_schedule_overrides;
create policy user_schedule_overrides_owner
  on public.user_schedule_overrides
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.user_schedule_overrides from anon;
grant select, insert, update, delete
  on public.user_schedule_overrides
  to authenticated;
