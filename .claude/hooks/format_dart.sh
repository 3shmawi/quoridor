#!/bin/bash
# PostToolUse(Edit|Write): dart format the edited file (skips generated code).
F=$(python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null)
case "$F" in
  *.g.dart|*.freezed.dart|*.config.dart|*.gr.dart) exit 0 ;;
  *.dart) [ -f "$F" ] && fvm dart format "$F" >/dev/null 2>&1 ;;
esac
exit 0
