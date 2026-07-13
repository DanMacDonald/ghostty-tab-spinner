#!/usr/bin/env bash
# PreToolUse: ALWAYS exit 0 — never deny tools. Keep fast.
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

hook_log "on-activity tool=${tool:-?} event=${GROK_HOOK_EVENT:-?}"

if is_user_input_tool "$tool"; then
  start_alert_loop 2>/dev/null || true
  exit 0
fi

# Normal tool / after answering a question: ensure braille is running.
stop_alert_loop 0 2>/dev/null || true
touch "$(busy_flag)" 2>/dev/null || true
touch "$(activity_file)" 2>/dev/null || true
ensure_spinner_loop 2>/dev/null || true
exit 0
