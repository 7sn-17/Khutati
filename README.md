# خطتي (Khutati)

Arabic-first, offline-first study plan app for the 68-day Professor MedX plan.
Flutter + Dart, SQLite via Drift, Supabase Auth (one-time Google sign-in), and a
native Kotlin layer for the background focus timer.

The approved HTML prototype (`خطتي اليومية، الإصدار 3.html`) is the design source
of truth. Plan content comes only from `khutati_plan_data.json` — never from code.

## Status

Phase 0 (foundation inputs) is complete:

- Flutter project skeleton with the PRD section 7 layering.
- Design tokens extracted from the prototype by script into `design/tokens.json`
  and generated into `lib/core/design/tokens.dart`.
- Arabic typography (IBM Plex Sans Arabic + Reem Kufi) bundled offline, RTL from
  the first frame.
- GitHub Actions pipeline that verifies tokens and data, then builds APKs.
- Dataset validator reconciling the plan to 480 h 9 min.

## Requirements

- Flutter 3.29.x (Dart 3.7)
- JDK 17
- Node.js 18+ (design-token and dataset tooling only)

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift codegen
flutter analyze
flutter test
flutter run

# Rebuild the design tokens after editing the prototype
node tools/extract_tokens.mjs
node tools/extract_tokens.mjs --check   # CI guard: fails on drift

# Re-validate the plan dataset against PRD section 3.1
node tools/validate_plan_data.mjs
node tools/validate_plan_data.mjs --self-test
```

## Layout

```
lib/
  app/            app shell, router, theme
  core/
    design/       generated tokens (do not edit), SVG parser, widget kit
    typography/   font entry points
    l10n/         Arabic strings (ARB migration in Phase 1.6)
    utils/        formatting helpers (digits, durations, Arabic time ranges)
    settings/     persisted preferences (theme mode)
  data/           Drift database and repositories
  domain/         plan engine, no Flutter imports (Phase 2)
  features/       today, plan, focus, achievements, gallery (debug)
tools/            token extraction, dataset validation
design/           generated tokens.json
docs/             generated data-validation report
android/          Kotlin host, foreground service (Phase 4.1)
```

## Design system

Every primitive is a port of a prototype rule, not an interpretation:

| Widget | Prototype source |
| --- | --- |
| `KCard` | `.hero` / `.pd` — card, hairline border, hexagon texture, optional accent |
| `KPill` | `.pill` — 32dp pill with gold value |
| `KTag` | `.tag` — solid subject colour, dark label |
| `KChip` | `.chip` — 52dp step toggle, `--ok` fill when pressed |
| `KButton` | `.btn` / `.btn2` — 44dp, red fill or hairline |
| `KProgressBar` | `.bar` — 8dp, rounded, `--redtx` |
| `KProgressRing` | `.ring` — 240dp, r104, 10px, round cap, -90° start |
| `KEcgLine` | `.ecg` — the exact path, mirrored, revealed in 600ms |
| `KBreakDivider` | `.br` — centred label between hairlines |
| `KSectionHeader` | `h2` — 24/12 margins |
| `KToast` / `KConfetti` | `#toast` / `.cf` — inverted pill, 26-piece burst |

`/gallery` renders all of them in the live theme (opened from Today in debug
builds). Tests diff the ECG path, ring geometry, hexagon tile and nav glyphs
against the HTML, so the prototype stays the source of truth.

## CI and signing

`.github/workflows/android.yml` runs on every push:

1. `node tools/extract_tokens.mjs --check` — the theme must match the prototype.
2. `node tools/validate_plan_data.mjs` — the dataset must reconcile to 480 h 9 min.
3. `flutter analyze` and `flutter test`.
4. Debug APK on every push; release APK on `main` and on `v*` tags.

Release signing uses these repository secrets (all optional; without them the
release APK is debug-signed):

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the release keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

## Conventions

- No colour, radius, or type size outside `lib/core/design/tokens.dart`.
- No plan content outside `khutati_plan_data.json`.
- No user-facing string literals in feature code; use `AppStrings` (ARB later).
- Layout uses directional properties (`start`/`end`), never `left`/`right`.
- Western digits everywhere (PRD section 13.1).
