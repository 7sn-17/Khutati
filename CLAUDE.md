# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

Read `PROJECT_CONTEXT.md` §7 first: CI is the only real gate. Locally:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze && flutter test

node tools/extract_tokens.mjs --check
node tools/check_version.mjs
node tools/validate_plan_data.mjs
node tools/validate_plan_data.mjs --self-test
```

## Architecture Overview

**Read `PROJECT_CONTEXT.md` before changing anything, then `ARCHITECTURE.md`.**

- Layering: `features` → `data` → `domain`; `core` is a leaf. `domain/` is pure
  Dart (no Flutter, no Drift).
- Offline-first: user writes go to Drift **then** the `sync_queue` outbox;
  `CloudSyncService` drains it every 5 minutes and on app pause. Never call
  Supabase from a widget or controller.
- The 4-tap step state machine lives in `lib/domain/plan/step_progress.dart`
  (codes 0/1/2/3; the two halves are distinct so the cycle survives a restart).
- Native bridge: `khutati/focus_timer` (methods) + `khutati/focus_events`
  (notification actions) in `android/app/src/main/kotlin/com/khutati/app/`.

## Conventions & Patterns

- The HTML prototype is the visual truth; design tokens are generated, never
  hand-written. No colour/radius/font size outside `lib/core/design/tokens.dart`.
- Dialogs are `KDialog` / `showKDialog`; there is no `showDialog` or `AlertDialog`
  in `lib/`. A dialog shown from `MaterialApp.builder` must use
  `rootNavigatorKey.currentContext`.
- Arabic UI and forced RTL. Shared strings go through `context.l10n`; numbers use
  Western digits via `core/utils/format.dart`.
- Generated Drift code (`*.g.dart`) is git-ignored — never hand-edit it, and check
  `@DataClassName` in `lib/data/database/tables.dart` before naming row types.
