#!/usr/bin/env bash
# PostToolUse: after ask_user_question, resume braille. Always exit 0.
set +e
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT/common.sh" 2>/dev/null || exit 0
set +e

should_run 2>/dev/null || exit 0

payload=""
if [[ ! -t 0 ]]; then
  payload="$(cat 2>/dev/null || true)"
fi
tool="$(read_hook_tool_name "$payload")"
[[ -z "$tool" ]] && tool="${GROK_TOOL_NAME:-${CLAUDE_TOOL_NAME:-}}"

hook_log "on-post-tool tool=${tool:-?} event=${GROK_HOOK_EVENT:-?}"

# Always re-assert busy spinner after tools (covers missed on-busy starts).
if is_user_input_tool "$tool" || [[ -f "$(alert_flag)" ]]; then
  stop_alert_loop 0 2>/dev/null || true
fi
touch "$(busy_flag)" 2>/dev/null || true
ensure_spinner_loop 2>/dev/null || true
exit 0
