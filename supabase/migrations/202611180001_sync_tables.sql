-- Offline-first cloud mirror for the three user-owned progress tables.
--
-- SQLite stays the source of truth. The Flutter client writes locally first and
-- drains a durable outbox in batches, so these tables are only a backup for
-- reinstalling on another phone. Every row is owned by auth.uid() and RLS
-- prevents a user from ever seeing another account's progress.

create table if not exists public.user_task_states (
  user_id uuid not null references auth.users (id) on delete cascade,
  task_id text not null,
  status text not null default 'not_started',
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, task_id)
);

create table if not exists public.user_step_states (
  user_id uuid not null references auth.users (id) on delete cascade,
  step_id text not null,
  progress smallint not null default 0,
  completed boolean not null default false,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, step_id)
);

create table if not exists public.focus_sessions (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  task_id text,
  task_title text,
  mode text not null default 'pomodoro',
  step_id text,
  phase text not null default 'focus',
  planned_seconds integer not null default 0,
  actual_seconds integer not null default 0,
  started_at timestamptz not null,
  ended_at timestamptz,
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create index if not exists idx_user_task_states_updated
  on public.user_task_states (user_id, updated_at desc);

create index if not exists idx_user_step_states_updated
  on public.user_step_states (user_id, updated_at desc);

create index if not exists idx_focus_sessions_updated
  on public.focus_sessions (user_id, started_at desc);

alter table public.user_task_states enable row level security;
alter table public.user_step_states enable row level security;
alter table public.focus_sessions enable row level security;

drop policy if exists user_task_states_owner on public.user_task_states;
create policy user_task_states_owner on public.user_task_states
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists user_step_states_owner on public.user_step_states;
create policy user_step_states_owner on public.user_step_states
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists focus_sessions_owner on public.focus_sessions;
create policy focus_sessions_owner on public.focus_sessions
  for all
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- The anon key is public; only a signed-in account may touch these rows.
revoke all on public.user_task_states from anon;
revoke all on public.user_step_states from anon;
revoke all on public.focus_sessions from anon;
grant select, insert, update, delete on public.user_task_states to authenticated;
grant select, insert, update, delete on public.user_step_states to authenticated;
grant select, insert, update, delete on public.focus_sessions to authenticated;
