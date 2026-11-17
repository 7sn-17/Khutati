#!/usr/bin/env node
/**
 * Extracts the Khutati design tokens from the approved HTML prototype and
 * generates:
 *   - design/tokens.json          (machine-readable, single source of truth)
 *   - lib/core/design/tokens.dart (generated Dart constants)
 *
 * The prototype is the design source of truth (PRD section 8). Tokens are
 * parsed, never hand-typed, so the Flutter theme cannot silently drift.
 *
 * Usage:
 *   node tools/extract_tokens.mjs           # write both files
 *   node tools/extract_tokens.mjs --check   # fail if generated files are stale
 */

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const HTML_FILE = 'خطتي اليومية، الإصدار 3.html';
const JSON_OUT = 'design/tokens.json';
const DART_OUT = 'lib/core/design/tokens.dart';

const REQUIRED_COLORS = [
  'bg', 'card', 'card2', 'line', 'tx', 'mute',
  'red', 'redtx', 'ok', 'gold',
];

const html = readFileSync(resolve(ROOT, HTML_FILE), 'utf8');
const styleMatch = html.match(/<style>([\s\S]*?)<\/style>/);
if (!styleMatch) fail(`no <style> block found in ${HTML_FILE}`);

const css = stripAtBlocks(
  styleMatch[1].replace(/\/\*[\s\S]*?\*\//g, ''),
  ['@media'],
);

/**
 * Removes at-rules with nested blocks (e.g. @media prefers-reduced-motion).
 * Those overrides are handled in Dart, not by the token extractor, and they
 * would otherwise clobber the base declarations during a flat parse.
 */
function stripAtBlocks(text, atNames) {
  let out = '';
  let i = 0;
  while (i < text.length) {
    const at = atNames.find((name) => text.startsWith(name, i));
    if (!at) {
      out += text[i++];
      continue;
    }
    let depth = 0;
    let j = i;
    for (; j < text.length; j++) {
      if (text[j] === '{') depth++;
      else if (text[j] === '}') {
        depth--;
        if (depth === 0) break;
      }
    }
    i = j + 1;
  }
  return out;
}

/** Flat CSS rules: selector -> declarations map. */
const rules = new Map();
for (const m of css.matchAll(/([^{}@]+)\{([^{}]*)\}/g)) {
  const selectors = m[1].split(',').map((s) => s.trim().replace(/\s+/g, ' '));
  for (const selector of selectors) {
    if (!selector) continue;
    const decls = rules.get(selector) ?? {};
    for (const d of m[2].split(';')) {
      const i = d.indexOf(':');
      if (i < 0) continue;
      decls[d.slice(0, i).trim()] = d.slice(i + 1).trim();
    }
    rules.set(selector, decls);
  }
}

function fail(msg) {
  console.error(`extract_tokens: ${msg}`);
  process.exit(1);
}

function rule(selector) {
  const r = rules.get(selector);
  if (!r) fail(`selector not found in prototype: ${selector}`);
  return r;
}

function decl(selector, prop) {
  const v = rule(selector)[prop];
  if (v === undefined) fail(`${selector} is missing "${prop}"`);
  return v;
}

function px(selector, prop) {
  const v = decl(selector, prop);
  const n = Number.parseFloat(v);
  if (Number.isNaN(n)) fail(`${selector}.${prop} is not a length: ${v}`);
  return n;
}

function seconds(selector, prop) {
  const v = decl(selector, prop);
  const m = v.match(/([\d.]+)s\b/);
  if (!m) fail(`${selector}.${prop} is not a duration: ${v}`);
  return Math.round(Number.parseFloat(m[1]) * 1000);
}

/** Expands a 1-4 value margin/padding shorthand into [top, right, bottom, left]. */
function box(selector, prop) {
  const parts = decl(selector, prop).split(/\s+/).map((p) => Number.parseFloat(p));
  if (parts.some(Number.isNaN)) fail(`${selector}.${prop} is not a box value`);
  const [t, r = t, b = t, l = r] = parts;
  return [t, r, b, l];
}

function hex(value, where) {
  const m = value.match(/#([0-9a-fA-F]{3,8})\b/);
  if (!m) fail(`${where} is not a hex colour: ${value}`);
  let h = m[1].toUpperCase();
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  if (h.length !== 6) fail(`${where} must be #RRGGBB: ${value}`);
  return `#${h}`;
}

/* ---------- colours ---------- */

function varsOf(selector) {
  const out = {};
  for (const [prop, value] of Object.entries(rule(selector))) {
    if (prop.startsWith('--')) out[prop.slice(2)] = value;
  }
  return out;
}

const darkVars = varsOf(':root');
const lightVars = { ...darkVars, ...varsOf(':root[data-theme=light]') };

const colors = { dark: {}, light: {} };
const inherited = [];
for (const key of REQUIRED_COLORS) {
  if (!(key in darkVars)) fail(`:root is missing --${key}`);
  colors.dark[key] = hex(darkVars[key], `--${key}`);
  colors.light[key] = hex(lightVars[key], `light --${key}`);
  if (!(key in varsOf(':root[data-theme=light]'))) inherited.push(key);
}

/* ---------- subject accents (declared in the prototype JS) ---------- */

const subjectMatch = html.match(/var C=\{([\s\S]*?)\};/);
if (!subjectMatch) fail('subject palette (var C={...}) not found');

const subjects = [];
for (const m of subjectMatch[1].matchAll(/(\w+):\['([^']+)','(#[0-9A-Fa-f]{6})'\]/g)) {
  subjects.push({ key: m[1], label: m[2], accent: m[3].toUpperCase() });
}
if (subjects.length !== 5) fail(`expected 5 subject accents, found ${subjects.length}`);

/* ---------- typography ---------- */

const bodyFont = decl('body', 'font');
const bodyParts = bodyFont.match(/^\s*(\d+)\s+(\d+(?:\.\d+)?)px\/(\d+(?:\.\d+)?)\s+"([^"]+)"/);
if (!bodyParts) fail(`cannot parse body font shorthand: ${bodyFont}`);

const displayFamily = decl('h1', 'font-family').match(/"([^"]+)"/)?.[1];
if (!displayFamily) fail('cannot parse heading font family');

const typography = {
  bodyFamily: bodyParts[4],
  bodyWeight: Number(bodyParts[1]),
  bodySize: Number(bodyParts[2]),
  bodyHeight: Number(bodyParts[3]),
  displayFamily,
  displayWeight: Number(decl('h1', 'font-weight')),
  h1Size: px('h1', 'font-size'),
  h1Height: Number(decl('h1', 'line-height')),
  h2Size: px('h2', 'font-size'),
  h2Top: box('h2', 'margin')[0],
  h2Bottom: box('h2', 'margin')[2],
  heroTitleSize: px('.hero h3', 'font-size'),
  ringNumeralSize: 58,
  ringCaptionSize: 16,
  navLabelSize: 12,
  pillSize: 13,
  smallSize: 13,
  muteSize: 14,
  tagSize: 12,
  counterSize: 13,
  statNumSize: px('.stat .num', 'font-size'),
  timelineNumSize: px('.pd .num', 'font-size'),
  levelNumSize: px('.lv .num', 'font-size'),
  bodyMaxWidth: px('.app', 'max-width'),
};

/* ---------- geometry / surfaces ---------- */

const metrics = {
  appPaddingX: 18,
  appPaddingTop: 16,
  appPaddingBottom: 130,
  cardRadius: px('.pd', 'border-radius'),
  heroRadius: px('.hero', 'border-radius'),
  navRadius: px('nav', 'border-radius'),
  navInset: 16,
  navBottom: 12,
  navPadding: 6,
  navItemRadius: 24,
  navIconSize: 22,
  pillRadius: 999,
  pillPaddingX: 12,
  pillPaddingY: 4,
  pillMinHeight: 32,
  buttonRadius: px('.btn', 'border-radius'),
  buttonMinHeight: px('.btn', 'min-height'),
  buttonPaddingX: 16,
  buttonPaddingY: 10,
  chipRadius: 12,
  chipMinHeight: px('.chip', 'min-height'),
  statRadius: px('.stat', 'border-radius'),
  levelRadius: px('.lv', 'border-radius'),
  timelineAccentWidth: 4,
  timelineRowMinHeight: 56,
  ringSize: px('.ring', 'width'),
  ringRadius: 104,
  ringStroke: 10,
  ecgHeight: px('.ecg', 'height'),
  ecgStroke: 2.5,
  barHeight: px('.bar', 'height'),
  barRadius: 4,
  mapColumns: 17,
  mapGap: 4,
  toastRadius: 999,
  toastBottom: 92,
  tapTarget: 48,
  gridGap: 8,
  sectionGap: 12,
  cardGap: 10,
};

/* ---------- motion ---------- */

const motion = {
  ecgMs: seconds('.ecg .p', 'transition'),
  navMs: seconds('nav button', 'transition'),
  toastMs: seconds('#toast', 'transition'),
  confettiMs: seconds('.cf', 'animation'),
  cardEntranceMs: 420,
  staggerMs: 70,
  pressScale: 0.97,
  standardCurve: 'easeInOutCubic',
  emphasizedCurve: 'easeOutCubic',
};

/* ---------- write ---------- */

const sourceSha = createHash('sha256').update(html).digest('hex');

const tokens = {
  $schema: 'khutati.design-tokens/1',
  generatedBy: 'tools/extract_tokens.mjs',
  source: { file: HTML_FILE, sha256: sourceSha },
  colors,
  colorInheritedFromDark: inherited,
  subjects,
  typography,
  metrics,
  motion,
};

function toDart() {
  const c = (v) => `Color(0xFF${v.slice(1)})`;
  const rows = (obj, indent = '  ') =>
    Object.entries(obj).map(([k, v]) => `${indent}static const ${typeOf(v)} ${k} = ${lit(v)};`).join('\n');

  const typeOf = (v) => (typeof v === 'string' ? 'String' : Number.isInteger(v) ? 'double' : 'double');
  const lit = (v) => (typeof v === 'string' ? `'${v}'` : Number.isInteger(v) ? v.toFixed(1) : String(v));

  const colorBlock = (name) =>
    Object.entries(colors[name])
      .map(([k, v]) => `    ${k}: ${c(v)},`)
      .join('\n');

  const subjectBlock = subjects
    .map((s) => `    '${s.key}': SubjectAccent(key: '${s.key}', label: '${s.label}', accent: ${c(s.accent)}),`)
    .join('\n');

  return `// GENERATED FILE - DO NOT EDIT BY HAND.
// Source: ${HTML_FILE} (sha256 ${sourceSha.slice(0, 12)})
// Regenerate with: node tools/extract_tokens.mjs
//
// Every colour, radius, size and duration in the app comes from here so the
// Flutter UI cannot drift from the approved HTML prototype.

import 'dart:ui' show Color;

/// Semantic colour tokens for one theme.
class KhutatiPalette {
  const KhutatiPalette({
${REQUIRED_COLORS.map((k) => `    required this.${k},`).join('\n')}
  });

${REQUIRED_COLORS.map((k) => `  final Color ${k};`).join('\n')}
}

/// Subject identity colour, taken from the prototype's subject palette.
class SubjectAccent {
  const SubjectAccent({required this.key, required this.label, required this.accent});

  final String key;
  final String label;
  final Color accent;
}

abstract final class KColors {
  static const KhutatiPalette dark = KhutatiPalette(
${colorBlock('dark')}
  );

  static const KhutatiPalette light = KhutatiPalette(
${colorBlock('light')}
  );

  static const Map<String, SubjectAccent> subjects = <String, SubjectAccent>{
${subjectBlock}
  };

  static SubjectAccent subject(String key) => subjects[key] ?? subjects['ch']!;
}

abstract final class KTypography {
  static const String bodyFamily = '${typography.bodyFamily}';
  static const String displayFamily = '${typography.displayFamily}';
  static const double bodySize = ${typography.bodySize.toFixed(1)};
  static const double bodyHeight = ${typography.bodyHeight.toFixed(1)};
  static const double h1Size = ${typography.h1Size.toFixed(1)};
  static const double h1Height = ${typography.h1Height.toFixed(1)};
  static const double h2Size = ${typography.h2Size.toFixed(1)};
  static const double heroTitleSize = ${typography.heroTitleSize.toFixed(1)};
  static const double ringNumeralSize = ${typography.ringNumeralSize.toFixed(1)};
  static const double statNumSize = ${typography.statNumSize.toFixed(1)};
  static const double timelineNumSize = ${typography.timelineNumSize.toFixed(1)};
  static const double levelNumSize = ${typography.levelNumSize.toFixed(1)};
  static const double navLabelSize = ${typography.navLabelSize.toFixed(1)};
  static const double pillSize = ${typography.pillSize.toFixed(1)};
  static const double smallSize = ${typography.smallSize.toFixed(1)};
  static const double muteSize = ${typography.muteSize.toFixed(1)};
  static const double tagSize = ${typography.tagSize.toFixed(1)};
  static const double counterSize = ${typography.counterSize.toFixed(1)};
}

abstract final class KMetrics {
${Object.entries(metrics).map(([k, v]) => `  static const double ${k} = ${v.toFixed(1)};`).join('\n')}
  static const double appMaxWidth = ${typography.bodyMaxWidth.toFixed(1)};
}

abstract final class KMotion {
${Object.entries(motion)
  .filter(([, v]) => typeof v === 'number')
  .map(([k, v]) =>
    Number.isInteger(v)
      ? `  static const int ${k} = ${v};`
      : `  static const double ${k} = ${v};`,
  )
  .join('\n')}
  static const String standardCurve = '${motion.standardCurve}';
  static const String emphasizedCurve = '${motion.emphasizedCurve}';
}
`;
}

const jsonText = `${JSON.stringify(tokens, null, 2)}\n`;
const dartText = toDart();

if (process.argv.includes('--check')) {
  let stale = false;
  for (const [path, expected] of [[JSON_OUT, jsonText], [DART_OUT, dartText]]) {
    let actual = '';
    try {
      actual = readFileSync(resolve(ROOT, path), 'utf8');
    } catch {
      console.error(`missing generated file: ${path}`);
      stale = true;
      continue;
    }
    if (actual !== expected) {
      console.error(`stale generated file: ${path} (run node tools/extract_tokens.mjs)`);
      stale = true;
    }
  }
  process.exit(stale ? 1 : 0);
}

for (const [path, text] of [[JSON_OUT, jsonText], [DART_OUT, dartText]]) {
  mkdirSync(dirname(resolve(ROOT, path)), { recursive: true });
  writeFileSync(resolve(ROOT, path), text, 'utf8');
  console.log(`wrote ${path}`);
}
console.log(`tokens: ${REQUIRED_COLORS.length} colours x 2 themes, ${subjects.length} subjects`);
