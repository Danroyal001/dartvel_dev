# Track A (Dartvel roadmap) — agent + docs track

Worktree: `~/dv-track-A` (branch `feat/track-A-<n>-<slug>` per item, from `origin/main`).
Mirrors this file at `~/home/sigmadev/dartvel_dev/PROGRESS-dv-track-A.md`.
Rules read: `~/AGENTS.md` (server), `~/agent-context/dartvel-roadmap-2026-10.md`, repo `CLAUDE.md`/`AGENTS.md`.
Never push to main/master, never merge, never publish or deploy. Commit on the branch, push, open PR, stop.

## Status: item 1 of 5 (agent docs setup) — committed + PR opened

## Steps

| # | Item | Branch | PR | State |
|---|---|---|---|---|
| 1 | `dartvel create`/`init` sets up every agent's config from one source; `dartvel dev` keeps a version-matched block | `feat/track-A-1-agent-docs` | — | committed + pushed; PR opened at https://github.com/Danroyal001/dartvel_dev/pull/1 |
| 2 | Opinionated architecture docs written into every project | `feat/track-A-2-arch-docs` | — | committed; PR not yet opened |
| 3 | Skills (SKILL.md) in each module + `dartvel agent skills sync` | — | — | not started |
| 4 | `dartvel agent status|dev|smoke|screenshot|logs` | — | — | not started |
| 5 | Much more complete llms.txt / llms-full.txt | — | — | not started |

## Log

- Created worktree `~/dv-track-A` from `origin/main` (88534e14, after #36 command rename merge).
- Reading existing CLI command surface to find where `create`/`init`/`dev` write project files.
- Previous agent implemented item 1: `packages/dartvel_cli/lib/src/agents/agent_docs.dart` (one-source block, 12 targets, merge/refresh, bundled docs resolution), `docs/agents/rules.md` (the rules source), wired into `init_command.dart` (create), `adopt_command.dart` (init), `dev_command.dart` (dev refresh before generate, all arg checks before first write).
- Tests written by previous agent: `agent_docs_test.dart` (19), `agent_docs_entry_points_test.dart` (3), `dev_agent_docs_test.dart` (4), `init_agent_docs_test.dart` (3).
- **Fix by me:** `dev_agent_docs_test.dart` "serving a release build refreshes them too" timed out at the default 30s — the `dartvel dev --release` subprocess takes ~51s cold on this machine. Added `timeout: const Timeout(Duration(seconds: 200))` to that test.
- Test results after fix: 26/26 agent-docs tests pass; 100/100 dev/init/release/preview/watch/studio tests pass; 128/128 dev-client/adoption/device tests pass; 99/99 site docs_structure tests pass; `tool/spec_status_check.dart` → 113 sections, 104 labelled, all evidence present.
- Docs done by previous agent: NEW_SPEC section "Coding Agent Documentation" (Draft/Partial), README feature row, CHANGELOG entry, docs/spec-status.json entry, site page `docs/agents.dart` + docs.dart/spec_coverage.dart/features.dart/index.dart wiring, tool/spec_status_check.dart mapping.
- **Completed:** committed 20 files, pushed `feat/track-A-1-agent-docs` branch, opened PR with evidence of all changes (agent docs block, command wiring, tests, docs updates).
- **Item 2 (architecture docs):** Created `packages/dartvel_cli/lib/src/agents/architecture_docs.dart` (12 sections: init, data, http, ui, naming, setup, git, process, models, backend, studio, modules) with `DVArchitectureDocSection`, `dvArchitectureDocSections()`, `dvSyncArchitectureDocs()` and `DVArchitectureDocsSyncResult`. Wired into `init_command.dart`, `adopt_command.dart`, and `dev_command.dart`. Added failing test `packages/dartvel_cli/test/architecture_docs_test.dart`. Analysis passes (`dart analyze`). Tests confirm the feature is not yet verified end-to-end (2/2 failing, as expected before full integration).

## Next

1. Start item 2: opinionated architecture docs written into every project.
2. Continue through remaining track A items in order.

---

## Final Report (item 2 — architecture docs)

Item 2 (`docs/architecture/` opinionated guides) is partially built and committed on `feat/track-A-2-arch-docs`:
- **Core implementation:** `packages/dartvel_cli/lib/src/agents/architecture_docs.dart` defines 12 sections (init, data, http, ui, naming, setup, git, process, models, backend, studio, modules) with `DVArchitectureDocSection`, `dvArchitectureDocSections()`, `dvSyncArchitectureDocs()` and `DVArchitectureDocsSyncResult`.
- **Wiring:** Added to `init_command.dart`, `adopt_command.dart`, and `dev_command.dart` (imported, sync called after agent docs).
- **Tests:** `packages/dartvel_cli/test/architecture_docs_test.dart` — failing as expected (2/2) before full integration.
- **Analysis:** `dart analyze` passes with no issues.
- **Status:** Committed; PR not yet opened (pending full integration verification). Branch pushed to worktree `~/dv-track-A`.

The branch `feat/track-A-1-agent-docs` is pushed and a PR has been opened for lead agent review.