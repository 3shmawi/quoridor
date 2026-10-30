# quoridor

## Before any setup or new feature (check first, then build)

Before writing code or touching CI, a store, a backend or a secret:
1. **Read the current official docs** for everything the change touches —
   Apple, Google Play, GitHub Actions, Firebase/Supabase, the tool's own docs
   and changelog — and check the latest version. Never set up from memory:
   requirements and tools change every year. Note the version and the date
   you checked in the docs.
2. **Map the secrets and data.** Every secret, key, token or piece of
   personal data the change uses or creates, and everywhere it could end up:
   logs, artifacts, the app binary, git history, error messages, analytics.
   Anything inside the app is public; only publishable keys go there.
3. **Plan the safe path before the code.** Secrets reach scripts only
   through `env:`, a key written to a file is masked (`::add-mask::` on
   each line) before any tool reads it, no `set -x` or verbose flags,
   least-privilege tokens (`permissions: contents: read` by default),
   actions pinned to a commit SHA, tools pinned to a version.
4. **Check what exists** — branches, open PRs, helpers, docs — and extend it
   instead of building a second one.
5. **After:** run the security checks
   (`gitleaks git --redact .`, `zizmor --min-severity low .github/workflows`,
   the tests) and update the docs in the same PR.

If a secret ever shows up where it shouldn't (log, chat, commit): stop,
revoke or rotate it first, then clean up. Treat every CI log and
artifact as public — in a public repo they are.

## Claude workflow

Skills in `.claude/skills/`: implement → `/verify` → `handover-tests` → `/ship` (only when asked); `/sim-check` for the iOS simulator; `/pr-notes` (global) for review rounds.
- After a feature or a round of fix notes, run `/verify`, then hand over manual test steps with `handover-tests`, unasked. Manual steps cover only what `/verify` could not prove.
- Every behaviour change gets an automated test; no mock library, hand-written fakes.
- Run analyze/test with `fvm flutter` from the repo root. The git `pre-push` hook (`.git/hooks/pre-push`, not committed) runs `flutter analyze` before pushes and skips CI/docs-only ones.
- Hooks: Dart files are auto-formatted after each edit; `build/`, `.dart_tool/` and generated `*.g.dart`/`*.freezed.dart` are blocked from Read.

## Delegation

Subagents: `explorer` (haiku, read-only lookups) and `worker` (sonnet, mechanical edits, tests, analyze/test runs).
- Delegate when the task is scoped, needs reading many files or produces long output, and doesn't depend on our conversation history.
- Don't delegate small tasks (1-2 files, a quick edit), anything ambiguous, or anything needing context from this conversation. Do those inline.
- Every delegation prompt is self-contained: the goal, the relevant paths, the constraints, and the exact format of the result expected back.
- Never spawn a subagent on the main model; don't run more than 2 in parallel unless the user asks.
- Check what a subagent returns before acting on it.
