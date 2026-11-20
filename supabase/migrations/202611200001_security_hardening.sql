-- Security hardening for the tables created by the earlier migrations.
--
-- Supabase grants every new table in `public` to `anon` and `authenticated` by
-- default. The RLS policies already protect the user tables, but two objects
-- were still over-exposed through PostgREST:
--
--   * `schema_migrations` had RLS disabled, so the public anon key could read,
--     insert, update or delete the migration ledger. Tampering with it could
--     make CI re-apply a migration or skip one entirely.
--   * `app_versions` is meant to be read-only for clients, yet it inherited
--     INSERT/UPDATE/DELETE/TRUNCATE grants. RLS happened to deny the writes,
--     but the privileges should not be there in the first place.
--
-- Nothing here changes the shape of the data or the client contract.

-- 1. The migration ledger is service-role only. The runner connects as the
--    table owner, so it keeps working; PostgREST roles lose all access.
alter table if exists public.schema_migrations enable row level security;
revoke all on table public.schema_migrations from anon, authenticated, public;

-- 2. Release metadata is public read-only; only the service role writes it.
revoke all on table public.app_versions from anon, authenticated, public;
grant select on table public.app_versions to anon, authenticated;

-- 3. User tables keep exactly the four DML privileges the client uses.
--    TRUNCATE, REFERENCES and TRIGGER are not part of the app's contract.
revoke all on table public.user_task_states from anon, authenticated, public;
revoke all on table public.user_step_states from anon, authenticated, public;
revoke all on table public.focus_sessions from anon, authenticated, public;
revoke all on table public.user_schedule_settings from anon, authenticated, public;
revoke all on table public.user_schedule_overrides from anon, authenticated, public;

grant select, insert, update, delete on table public.user_task_states to authenticated;
grant select, insert, update, delete on table public.user_step_states to authenticated;
grant select, insert, update, delete on table public.focus_sessions to authenticated;
grant select, insert, update, delete on table public.user_schedule_settings to authenticated;
grant select, insert, update, delete on table public.user_schedule_overrides to authenticated;
