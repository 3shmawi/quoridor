---
name: verify
description: Prove that a change or a round of fix notes does what was asked, with automated tests and a simulator run, before the manual hand-over. Use after implementing a feature/notes, before /ship, or when the user asks "verify", "make sure it works". Has a read-only mode that changes no code.
argument-hint: [readonly] [what to verify]
---

Goal: the user should only manually test what cannot be proven here. Output a report, not a wall of logs.

**Mode.** `readonly` (or the user is mid-change): do not create or edit any file; only run checks, read code and drive the simulator. Otherwise you may add tests (never production code without asking).

1. **Criteria**: number what was asked (the request or the fix notes). If unclear, ask.
2. **Map to code**: what changed (`git diff origin/main...HEAD --stat` plus `git status`). For each criterion, name the code (`path:line`) or mark it ❌ not implemented. Delegate to `explorer` if many files.
3. **Map to tests**: for each criterion find a test that proves it; missing → write it (non-readonly) following the tests in `test/` (hand-written fakes, no mock library; `fake_async` for timers; widget tests assert visible state).
4. **Run checks** (delegate to `worker`, failures only): `fvm flutter analyze` then `fvm flutter test` (or the specific files).
5. **Simulator** (UI changes): `/sim-check` the affected screens.
6. **Report** (table): criterion → code → proof (test / screenshot / ❌) → ✅ / ⚠️ / ❌. Then failures with `path:line` and what is still manual. Then run `handover-tests` covering only what is still manual.
