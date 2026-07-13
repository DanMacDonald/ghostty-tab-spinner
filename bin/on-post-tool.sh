#!/usr/bin/env bash
# PostToolUse: clear alert after ask_user_question; re-assert busy spinner.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh" 2>/dev/null || exit 0
set +e

payload=""
[[ ! -t 0 ]] && payload="$(cat 2>/dev/null || true)"
tool="$(read_hook_tool_name "$payload")"
[[ -z "$tool" ]] && tool="${GROK_TOOL_NAME:-${CLAUDE_TOOL_NAME:-}}"

hook_log "on-post-tool tool=${tool:-?} event=${GROK_HOOK_EVENT:-?}"

if is_user_input_tool "$tool" || [[ -f "$(alert_flag)" ]]; then
  stop_alert_loop 0 2>/dev/null || true
fi
touch "$(busy_flag)" 2>/dev/null || true
ensure_spinner_loop 2>/dev/null || true
exit 0
