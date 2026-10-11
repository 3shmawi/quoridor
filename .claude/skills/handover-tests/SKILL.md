---
name: handover-tests
description: Write the full manual test hand-over after a feature or a round of fix notes is finished. Use at the end of every such round, unasked, or when the user says "test steps", "handover", "how do I test this".
---

End with the full set of manual test steps for what changed. Base it on the request and the actual diff (`git diff origin/main...HEAD --stat` plus uncommitted changes), not memory.

1. **Setup**: the run command (`fvm flutter run` plus any `-t` entry point or flags this app uses) and the state needed (which level/screen, settings, data).
2. **Scenarios**: one numbered scenario per behaviour that changed, each with steps and expected result (✅). Cover the happy path, every variant, error states, and regressions in nearby flows.
3. **Languages / theme / orientation** when there is new text or a new layout.
4. **Coverage note**: mark which scenarios `/verify` already proved so the user only runs the rest. Say plainly what was not tested on a device.
