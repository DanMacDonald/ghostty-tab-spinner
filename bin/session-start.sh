#!/usr/bin/env bash
# SessionStart: set idle project title. Re-assert a few times — Grok/Ghostty
# often stamps "grok" onto the tab right after load/resume.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

hook_log "session-start enter session=${GROK_SESSION_ID:-?}"

capture_tty >/dev/null 2>&1
title="$(idle_title)"
set_title_osc "$title" || true
hook_log "session-start title=${title} tty=$(cat "$(session_dir)/tty" 2>/dev/null || echo none)"

(
  export GROK_SESSION_ID="${GROK_SESSION_ID:-default}"
  export GROK_PLUGIN_DATA="${GROK_PLUGIN_DATA:-$(plugin_data)}"
  export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(plugin_root)}"
  export GROK_WORKSPACE_ROOT="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-${PWD:-}}}"
  # shellcheck source=common.sh
  source "$_GTS_BIN_DIR/common.sh"
  for delay in 0.3 0.8 1.5 3.0; do
    sleep "$delay" 2>/dev/null || sleep 1
    if [[ -f "$(busy_flag)" ]] || [[ -f "$(alert_flag)" ]]; then
      hook_log "session-start reassert skip (busy/alert) after ${delay}s"
      exit 0
    fi
    set_title_osc "$(idle_title)" || true
    hook_log "session-start reassert title=$(idle_title) after ${delay}s"
  done
) </dev/null >>"$(session_dir)/session-start.stderr" 2>&1 &
disown 2>/dev/null || true

exit 0
