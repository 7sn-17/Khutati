#!/usr/bin/env node
// Applies `supabase/migrations/*.sql` to the hosted project, in filename order.
//
// Why this exists: the migrations are plain SQL and the app ships ahead of
// them, so a forgotten `user_schedule_overrides` table silently breaks cloud
// sync. Running them from CI means a merge to `main` cannot leave the backend
// behind the client.
//
// How it talks to Supabase: the Management API's "run SQL" endpoint, which
// needs a Personal Access Token (`sbp_…`) — the service-role key can read and
// write rows but cannot run DDL. Both values come from the environment and are
// never written to disk.
//
//   SUPABASE_URL            https://<ref>.supabase.co   (or SUPABASE_PROJECT_REF)
//   SUPABASE_ACCESS_TOKEN   sbp_…
//
// Applied filenames are recorded in `public.schema_migrations`, and each
// migration is committed together with its ledger row, so a failure leaves the
// database exactly as it was and the next run retries the same file.
//
//   node tools/apply_migrations.mjs            apply pending
//   node tools/apply_migrations.mjs --dry-run  list pending, change nothing

import {readdirSync, readFileSync} from 'node:fs';
import {join} from 'node:path';

const MIGRATIONS_DIR = join('supabase', 'migrations');
const LEDGER = 'public.schema_migrations';
const API = 'https://api.supabase.com/v1';
const DRY_RUN = process.argv.includes('--dry-run');

const token = (process.env.SUPABASE_ACCESS_TOKEN ?? '').trim();
const url = (process.env.SUPABASE_URL ?? '').trim();
const explicitRef = (process.env.SUPABASE_PROJECT_REF ?? '').trim();

function projectRef() {
  if (explicitRef) return explicitRef;
  const match = /^https?:\/\/([a-z0-9]+)\.supabase\.co\/?$/i.exec(url);
  if (!match) {
    throw new Error(
      'Cannot derive the project ref: set SUPABASE_URL=https://<ref>.supabase.co ' +
        'or SUPABASE_PROJECT_REF.',
    );
  }
  return match[1];
}

function localMigrations() {
  return readdirSync(MIGRATIONS_DIR)
    .filter((name) => name.endsWith('.sql'))
    .sort();
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

/** POSTs one SQL string, retrying transient failures. Returns the rows. */
async function runSql(ref, sql, attempt = 1) {
  const response = await fetch(`${API}/projects/${ref}/database/query`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({query: sql}),
  });

  if (response.ok) {
    const text = await response.text();
    if (text.trim() === '') return [];
    const parsed = JSON.parse(text);
    if (Array.isArray(parsed)) return parsed;
    // The endpoint has also answered with {result: [...]} in older versions.
    return Array.isArray(parsed.result) ? parsed.result : [];
  }

  const body = (await response.text()).slice(0, 2000);
  const retryable = response.status === 429 || response.status >= 500;
  if (retryable && attempt < 3) {
    await sleep(attempt * 2000);
    return runSql(ref, sql, attempt + 1);
  }
  throw new Error(`Supabase returned ${response.status}: ${body}`);
}

async function appliedMigrations(ref) {
  await runSql(
    ref,
    `create table if not exists ${LEDGER} (
       filename text primary key,
       applied_at timestamptz not null default now()
     );`,
  );
  const rows = await runSql(
    ref,
    `select filename from ${LEDGER} order by filename;`,
  );
  return new Set(rows.map((row) => row.filename));
}

function quote(value) {
  return `'${value.replaceAll("'", "''")}'`;
}

async function main() {
  if (!token) {
    console.log(
      '::warning::SUPABASE_ACCESS_TOKEN is not configured; skipping migrations.',
    );
    return;
  }

  const ref = projectRef();
  const files = localMigrations();
  if (files.length === 0) {
    console.log('No migration files found; nothing to do.');
    return;
  }

  const applied = await appliedMigrations(ref);
  const pending = files.filter((name) => !applied.has(name));

  if (pending.length === 0) {
    console.log(`All ${files.length} migrations are already applied.`);
    return;
  }

  console.log(`Pending: ${pending.join(', ')}`);
  if (DRY_RUN) return;

  for (const name of pending) {
    const sql = readFileSync(join(MIGRATIONS_DIR, name), 'utf8').trim();
    if (sql.length === 0) {
      throw new Error(`${name} is empty.`);
    }
    await runSql(
      ref,
      `begin;\n${sql}\ninsert into ${LEDGER} (filename) values (${quote(name)});\ncommit;`,
    );
    console.log(`Applied ${name}`);
  }

  console.log(`Done: ${pending.length} migration(s) applied.`);
}

main().catch((error) => {
  console.error(`::error::${error.message}`);
  process.exitCode = 1;
});
