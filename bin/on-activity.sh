#!/usr/bin/env bash
# PreToolUse: keep spinner alive; ask_user_question → Action Required.
#
# No tool matcher on purpose: spinner must survive every tool in a turn.
# ALWAYS exit 0 — never deny tools, never inspect tool args beyond name.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh" 2>/dev/null || exit 0
set +e

payload=""
[[ ! -t 0 ]] && payload="$(cat 2>/dev/null || true)"
tool="$(read_hook_tool_name "$payload")"
[[ -z "$tool" ]] && tool="${GROK_TOOL_NAME:-${CLAUDE_TOOL_NAME:-}}"

hook_log "on-activity tool=${tool:-?} event=${GROK_HOOK_EVENT:-?}"

if is_user_input_tool "$tool"; then
  start_alert_loop 2>/dev/null || true
  exit 0
fi

stop_alert_loop 0 2>/dev/null || true
touch "$(busy_flag)" 2>/dev/null || true
ensure_spinner_loop 2>/dev/null || true
exit 0
