#!/bin/bash
# Stop: refresh the graphify graph in the background when Dart files changed.
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0
command -v graphify >/dev/null || exit 0
[ -f graphify-out/graph.json ] || exit 0
if git status --porcelain -- '*.dart' | grep -q . || [ -n "$(find . -name '*.dart' -newer graphify-out/graph.json -not -path './build/*' -not -path '*/.dart_tool/*' -print -quit 2>/dev/null)" ]; then
  (graphify update . >/dev/null 2>&1 &)
fi
exit 0
