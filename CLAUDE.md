# quoridor

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
