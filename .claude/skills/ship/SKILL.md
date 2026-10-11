---
name: ship
description: Commit and push finished work. Use when the user says commit, ship, push. Only on explicit request.
argument-hint: [commit | push]
---

- Commit messages follow the style of recent `git log` (plain sentence saying what the player/user now gets). One logical change per commit.
- Run `/verify` checks (analyze + tests) first; don't commit with failures unless the user says so.
- Before any `git push` the `pre-push` hook runs `flutter analyze` and stops a push with errors; fix them, never bypass with SKIP_VALIDATE unless the user says so.
- Never push unless the user asked for a push in this request. After pushing, check the GitHub Actions run (`gh run list -L 3`) and fix failures.
