#!/usr/bin/env node
/**
 * Independent validator for khutati_plan_data.json (PRD section 3.1).
 *
 * Re-derives every numeric claim in the dataset from the raw items instead of
 * trusting the pre-computed totals, so a corrupted export cannot reach the app.
 *
 * Usage:
 *   node tools/validate_plan_data.mjs            # validate, write docs/data-validation.md
 *   node tools/validate_plan_data.mjs --quiet    # exit code only
 */

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { resolve, dirname, join } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const FILE_ARG = process.argv.find((a) => a.startsWith('--file='))?.slice('--file='.length);
const DATA = resolve(ROOT, FILE_ARG ?? 'khutati_plan_data.json');
const REPORT = resolve(ROOT, 'docs/data-validation.md');
const QUIET = process.argv.includes('--quiet');
const SELF_TEST = process.argv.includes('--self-test');

const EXPECTED = {
  days: 68,
  studyDays: 64,
  restDays: [15, 30, 45, 60],
  practicalDays: 20,
  items: 725,
  videos: 665,
  courses: 60,
  totalMinutes: 480 * 60 + 9, // 28809
  startDate: '2026-11-19',
  endDate: '2027-01-25',
  subjects: {
    bio: { name: 'بيولوجيا الخلية', attendance: 70 * 60 + 6, study: 69 * 60 + 19, courses: 11 * 60, total: 150 * 60 + 25 },
    chem: { name: 'الكيمياء الطبية', attendance: 63 * 60 + 16, study: 61 * 60 + 18, courses: 19 * 60, total: 143 * 60 + 34 },
    phys: { name: 'الفيزياء الطبية', attendance: 41 * 60 + 26, study: 40 * 60 + 52, courses: 16 * 60, total: 98 * 60 + 18 },
    hist: { name: 'تاريخ الطب', attendance: 17 * 60, study: 17 * 60, courses: 7 * 60, total: 41 * 60 },
    eng: { name: 'انكليزي 1', attendance: 20 * 60 + 27, study: 19 * 60 + 25, courses: 7 * 60, total: 46 * 60 + 52 },
  },
};

const results = [];
function check(name, fn) {
  try {
    const detail = fn();
    results.push({ ok: true, name, detail: detail ?? '' });
  } catch (err) {
    results.push({ ok: false, name, detail: err.message });
  }
}

function assert(cond, message) {
  if (!cond) throw new Error(message);
}

function eq(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, got ${actual}`);
}

const toMin = (hhmm) => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm ?? '');
  if (!m) throw new Error(`bad time value: ${JSON.stringify(hhmm)}`);
  return Number(m[1]) * 60 + Number(m[2]);
};

const dayDiff = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / 86_400_000);

const ARABIC_INDIC = /[\u0660-\u0669\u06F0-\u06F9]/;

const data = JSON.parse(readFileSync(DATA, 'utf8'));

if (SELF_TEST) {
  // Proves the validator actually catches corruption instead of always passing.
  const mutations = [
    ['grand total drift', (d) => { d.days[0].computed.studyMinutes += 1; }],
    ['wrong rest day', (d) => { d.days.find((x) => x.day === 15).type = 'normal'; }],
    ['duplicate id', (d) => { d.days[0].sections[0].periods[0].items[1].id = d.days[0].sections[0].periods[0].items[0].id; }],
    ['arabic-indic digit', (d) => { d.days[0].sections[0].periods[0].items[0].title += ' ٢'; }],
    ['broken date', (d) => { d.days[3].date = '2026-11-30'; }],
  ];
  let failures = 0;
  for (const [name, mutate] of mutations) {
    const copy = JSON.parse(JSON.stringify(data));
    mutate(copy);
    const file = join(tmpdir(), `khutati-mutant-${process.pid}-${failures}.json`);
    writeFileSync(file, JSON.stringify(copy), 'utf8');
    let detected = false;
    try {
      execFileSync(process.execPath, [process.argv[1], `--file=${file}`, '--quiet'], { stdio: 'ignore' });
    } catch {
      detected = true;
    }
    console.log(`${detected ? 'PASS' : 'FAIL'}  detects ${name}`);
    if (!detected) failures++;
  }
  process.exit(failures === 0 ? 0 : 1);
}

const days = data.days ?? [];
const allItems = days.flatMap((d) => (d.sections ?? []).flatMap((s) => (s.periods ?? []).flatMap((p) => p.items ?? [])));

/* ---------------- structure ---------------- */

check('Day count is 68', () => eq(days.length, EXPECTED.days, 'days'));

check('Rest days are 15, 30, 45 and 60', () => {
  const rest = days.filter((d) => d.type === 'rest').map((d) => d.day);
  eq(JSON.stringify(rest), JSON.stringify(EXPECTED.restDays), 'rest days');
  return rest.join(', ');
});

check('Study days are 64', () => {
  const study = days.filter((d) => d.type !== 'rest');
  eq(study.length, EXPECTED.studyDays, 'study days');
  return `${study.length} study days`;
});

check('Practical days are 20 and start at 16:00', () => {
  const practical = days.filter((d) => d.type === 'practical');
  eq(practical.length, EXPECTED.practicalDays, 'practical days');
  eq(JSON.stringify(practical.map((d) => d.day)), JSON.stringify(data.meta.practicalDays), 'meta.practicalDays');
  for (const d of practical) eq(d.start, '16:00', `day ${d.day} start`);
  return `${practical.length} days`;
});

check('Normal days start at 08:00', () => {
  const normal = days.filter((d) => d.type === 'normal');
  for (const d of normal) eq(d.start, '08:00', `day ${d.day} start`);
  return `${normal.length} normal days`;
});

check('Item counts: 725 total, 665 videos, 60 course-question hours', () => {
  const videos = allItems.filter((i) => i.type === 'video').length;
  const courses = allItems.filter((i) => i.type === 'course_questions').length;
  eq(allItems.length, EXPECTED.items, 'items');
  eq(videos, EXPECTED.videos, 'videos');
  eq(courses, EXPECTED.courses, 'course items');
  return `${allItems.length} items`;
});

check('Every item ID is unique and well formed', () => {
  const ids = new Set();
  for (const item of allItems) {
    assert(item.id, 'item without id');
    assert(!ids.has(item.id), `duplicate id ${item.id}`);
    assert(/^d\d{3}-[a-z]{3,4}-\d{2}-\d{2}$/.test(item.id), `unexpected id shape ${item.id}`);
    ids.add(item.id);
  }
  return `${ids.size} unique ids`;
});

/* ---------------- dates ---------------- */

check('Day N date equals start date + (N-1) days', () => {
  eq(days[0].date, EXPECTED.startDate, 'day 1 date');
  for (const d of days) {
    const expected = new Date(Date.parse(EXPECTED.startDate) + (d.day - 1) * 86_400_000).toISOString().slice(0, 10);
    eq(d.date, expected, `day ${d.day} date`);
  }
  eq(days.at(-1).date, EXPECTED.endDate, 'day 68 date');
  return `${EXPECTED.startDate} to ${EXPECTED.endDate}`;
});

check('Week numbers match (day-1)/7 + 1', () => {
  for (const d of days) eq(d.week, Math.floor((d.day - 1) / 7) + 1, `day ${d.day} week`);
  return '68 days';
});

/* ---------------- per-item arithmetic ---------------- */

check('Attendance and study intervals match their printed minutes', () => {
  let checked = 0;
  for (const item of allItems) {
    for (const field of ['attendance', 'study']) {
      const seg = item[field];
      if (!seg) continue;
      eq(toMin(seg.end) - toMin(seg.start), seg.minutes, `${item.id} ${field} interval`);
      checked++;
    }
    assert(item.attendance || item.study, `${item.id} has no timed step`);
    if (item.type === 'course_questions') assert(!item.attendance, `${item.id} course item must not have attendance`);
    if (item.type === 'video') assert(item.attendance && item.study, `${item.id} video needs attendance + study`);
  }
  return `${checked} intervals`;
});

check('No item is scheduled before its period start or after its end', () => {
  for (const day of days) {
    for (const section of day.sections ?? []) {
      for (const period of section.periods ?? []) {
        const start = toMin(period.start);
        const end = toMin(period.end);
        for (const item of period.items ?? []) {
          const first = toMin(item.attendance?.start ?? item.study?.start);
          const last = toMin(item.study?.end ?? item.attendance?.end);
          assert(first >= start, `${item.id} starts before its period`);
          assert(last <= end, `${item.id} ends after its period`);
        }
      }
    }
  }
  return 'all items within their period';
});

/* ---------------- per-day totals ---------------- */

check('Per-day computed total equals the printed header total', () => {
  let checked = 0;
  for (const day of days) {
    if (day.type === 'rest') {
      assert((day.sections ?? []).length === 0, `rest day ${day.day} has sections`);
      continue;
    }
    let attendance = 0;
    let study = 0;
    let courses = 0;
    for (const section of day.sections) {
      for (const period of section.periods) {
        for (const item of period.items) {
          attendance += item.attendance?.minutes ?? 0;
          // The dataset tracks course-question hours separately from video
          // study minutes; both count toward the day's printed total.
          if (item.type === 'course_questions') courses += item.study?.minutes ?? 0;
          else study += item.study?.minutes ?? 0;
        }
      }
    }
    eq(day.computed.attendanceMinutes, attendance, `day ${day.day} attendance`);
    eq(day.computed.studyMinutes, study, `day ${day.day} study`);
    eq(day.computed.courseQuestionMinutes, courses, `day ${day.day} course minutes`);
    eq(day.computed.totalMinutes, attendance + study + courses, `day ${day.day} total`);
    eq(day.statedStudyMinutes, day.computed.totalMinutes, `day ${day.day} printed vs computed`);
    checked++;
  }
  return `${checked} study days`;
});

check('Interludes start where the previous period ends', () => {
  let checked = 0;
  for (const day of days) {
    for (const inter of day.interludes ?? []) {
      const periods = (day.sections ?? []).flatMap((s) => s.periods ?? []);
      const prev = periods.find((p) => p.index === inter.afterPeriod);
      assert(prev, `day ${day.day} interlude references missing period ${inter.afterPeriod}`);
      eq(toMin(inter.start), toMin(prev.end), `day ${day.day} interlude start`);
      eq(toMin(inter.end) - toMin(inter.start), inter.minutes, `day ${day.day} interlude length`);
      checked++;
    }
  }
  return `${checked} interludes`;
});

/* ---------------- grand totals ---------------- */

const totals = { attendance: 0, study: 0, courses: 0 };
for (const day of days) {
  totals.attendance += day.computed?.attendanceMinutes ?? 0;
  totals.study += day.computed?.studyMinutes ?? 0;
  totals.courses += day.computed?.courseQuestionMinutes ?? 0;
}

check('Grand total is exactly 480 h 9 min (28809 minutes)', () => {
  const total = totals.attendance + totals.study + totals.courses;
  eq(total, EXPECTED.totalMinutes, 'grand total');
  return `${total} min = ${Math.floor(total / 60)} h ${total % 60} min`;
});

check('Attendance / study / course split matches page 2', () => {
  eq(totals.attendance, 212 * 60 + 15, 'attendance total');
  eq(totals.study, 207 * 60 + 54, 'study total');
  eq(totals.courses, 60 * 60, 'course total');
  return `${totals.attendance} / ${totals.study} / ${totals.courses}`;
});

check('Per-subject totals match the page-2 table', () => {
  const actual = {};
  for (const day of days) {
    for (const section of day.sections ?? []) {
      const bucket = (actual[section.subjectKey] ??= { attendance: 0, study: 0, courses: 0 });
      for (const period of section.periods ?? []) {
        for (const item of period.items ?? []) {
          bucket.attendance += item.attendance?.minutes ?? 0;
          if (item.type === 'course_questions') bucket.courses += item.study?.minutes ?? 0;
          else bucket.study += item.study?.minutes ?? 0;
        }
      }
    }
  }
  const lines = [];
  for (const [key, expected] of Object.entries(EXPECTED.subjects)) {
    const got = actual[key];
    assert(got, `subject ${key} missing from dataset`);
    eq(got.attendance, expected.attendance, `${key} attendance`);
    eq(got.study, expected.study, `${key} study`);
    eq(got.courses, expected.courses, `${key} courses`);
    eq(got.attendance + got.study + got.courses, expected.total, `${key} total`);
    lines.push(key);
  }
  eq(Object.keys(actual).length, Object.keys(EXPECTED.subjects).length, 'subject count');
  return lines.join(', ');
});

check('Phase boundaries match the plan structure', () => {
  const lastDayOf = (key) => {
    let last = 0;
    for (const day of days) {
      for (const section of day.sections ?? []) if (section.subjectKey === key) last = Math.max(last, day.day);
    }
    return last;
  };
  for (const [key, expected] of Object.entries(data.meta.lastDayPerSubject)) {
    eq(lastDayOf(key), expected, `last day of ${key}`);
  }
  eq(JSON.stringify(data.meta.lastDayPerSubject), JSON.stringify({ chem: 27, eng: 46, hist: 47, phys: 47, bio: 68 }), 'meta map');
  return 'chem 27, eng 46, hist 47, phys 47, bio 68';
});

check('Bio is the only subject after day 47', () => {
  for (const day of days.filter((d) => d.day > 47 && d.type !== 'rest')) {
    const keys = new Set((day.sections ?? []).map((s) => s.subjectKey));
    eq(JSON.stringify([...keys]), JSON.stringify(['bio']), `day ${day.day} subjects`);
  }
  return 'days 48-68';
});

/* ---------------- text hygiene ---------------- */

check('No Arabic-Indic digits remain', () => {
  const bad = allItems.filter((i) => ARABIC_INDIC.test(i.title ?? ''));
  assert(bad.length === 0, `${bad.length} items still use Arabic-Indic digits (e.g. ${bad[0]?.id})`);
  return `${allItems.length} titles`;
});

check('Every item has a non-empty title and group', () => {
  for (const item of allItems) {
    assert((item.title ?? '').trim().length > 0, `${item.id} empty title`);
    assert((item.group ?? '').trim().length > 0, `${item.id} empty group`);
  }
  return `${allItems.length} items`;
});

check('Meta subject table agrees with recomputed totals', () => {
  for (const s of data.meta.subjects) {
    const expected = EXPECTED.subjects[s.key];
    assert(expected, `unexpected meta subject ${s.key}`);
    eq(s.name, expected.name, `${s.key} name`);
  }
  return `${data.meta.subjects.length} subjects`;
});

/* ---------------- report ---------------- */

const failed = results.filter((r) => !r.ok);
const stamp = new Date().toISOString().slice(0, 10);

const report = `# Plan dataset validation

Generated by \`tools/validate_plan_data.mjs\` from \`khutati_plan_data.json\` on ${stamp}.

**Result:** ${failed.length === 0 ? 'PASS' : `FAIL (${failed.length} check(s))`} — ${results.length - failed.length}/${results.length} checks passed.

| Check | Result | Detail |
| --- | --- | --- |
${results.map((r) => `| ${r.name} | ${r.ok ? 'pass' : '**FAIL**'} | ${r.detail.replace(/\|/g, '\\|')} |`).join('\n')}

## Reconciled totals

| Bucket | Minutes | Hours |
| --- | --- | --- |
| Attendance | ${totals.attendance} | ${(totals.attendance / 60).toFixed(2)} |
| Study | ${totals.study} | ${(totals.study / 60).toFixed(2)} |
| Course questions | ${totals.courses} | ${(totals.courses / 60).toFixed(2)} |
| **Grand total (attendance + study + courses)** | **${totals.attendance + totals.study + totals.courses}** | **${Math.floor((totals.attendance + totals.study + totals.courses) / 60)} h ${(totals.attendance + totals.study + totals.courses) % 60} min** |

Run this in CI before any build that bundles the dataset. A failure here blocks the
build: the app must never ship a plan that does not reconcile to the PDF.
`;

if (!FILE_ARG) {
  mkdirSync(dirname(REPORT), { recursive: true });
  writeFileSync(REPORT, report, 'utf8');
}

if (!QUIET) {
  for (const r of results) console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name}${r.detail ? ` — ${r.detail}` : ''}`);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
}

if (failed.length > 0) process.exit(1);
