-- Removes the first update table, superseded by `app_versions`.
--
-- `app_updates` was a per-platform/per-channel manifest read first by the
-- client. The waterfall now goes GitHub API -> GitHub Atom -> Supabase, and
-- `app_versions` holds only what the last step needs, so the old table is dead
-- weight: no client reads it and nothing writes to it.
--
-- The create migration was deleted at the same time, so a fresh project never
-- builds the table. This statement only matters for a database that already
-- applied it.

drop table if exists public.app_updates;
