-- Cross-device practical-weekday setting.
--
-- One row per account. `practical_weekdays` is a JSON array of two ISO weekday
-- numbers (1 = Monday ... 7 = Sunday). An empty array means "use the bundled
-- original schedule", which is how a reset travels to another device.
--
-- The local SQLite setting remains the source of truth while offline; the
-- existing sync_queue outbox uploads the latest snapshot and this row is only
-- read when a newer account state is pulled.

create table if not exists public.user_schedule_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  practical_weekdays jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_schedule_settings enable row level security;

drop policy if exists user_schedule_settings_owner
  on public.user_schedule_settings;
create policy user_schedule_settings_owner
  on public.user_schedule_settings
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.user_schedule_settings from anon;
grant select, insert, update, delete
  on public.user_schedule_settings
  to authenticated;
