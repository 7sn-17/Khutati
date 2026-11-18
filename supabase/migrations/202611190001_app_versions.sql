-- Public release history for the in-app update waterfall.
--
-- The client asks GitHub first (API, then the static Atom feed) and only
-- queries this table when both fail — for example when github.com itself is
-- unreachable, or the device is behind a network that blocks it. Only public
-- release metadata lives here: never store user data.
--
-- Writes come from CI (service role) on every published release, so the newest
-- row always describes the APK that is currently on GitHub.

create table if not exists public.app_versions (
  id uuid primary key default gen_random_uuid(),
  version text not null,
  download_url text not null,
  release_notes text,
  created_at timestamptz not null default now()
);

-- One row per version, so CI can upsert instead of appending duplicates.
create unique index if not exists idx_app_versions_version
  on public.app_versions (version);

create index if not exists idx_app_versions_created_at
  on public.app_versions (created_at desc);

alter table public.app_versions enable row level security;

-- The release list is public by design; writes stay with the service role.
drop policy if exists app_versions_public_read on public.app_versions;
create policy app_versions_public_read
  on public.app_versions
  for select
  to anon, authenticated
  using (true);

grant select on public.app_versions to anon, authenticated;

-- Seed the release that is live at the time this migration is applied.
insert into public.app_versions (version, download_url, release_notes)
select
  '0.8.7+37',
  'https://github.com/7sn-17/Khutati/releases/latest/download/Khutati.apk',
  'الإصدار الأول المتاح عبر احتياطي Supabase.'
where not exists (
  select 1 from public.app_versions where version = '0.8.7+37'
);
