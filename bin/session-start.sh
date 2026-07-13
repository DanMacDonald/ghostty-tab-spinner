#!/usr/bin/env bash
# Session start: capture TTY, set idle project title (Codex-style).
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

hook_log "session-start enter session=${GROK_SESSION_ID:-?}"

if ! should_run; then
  exit 0
fi

capture_tty >/dev/null 2>&1
set_title_osc "$(idle_title)" || true
hook_log "session-start title=$(idle_title) tty=$(cat "$(session_dir)/tty" 2>/dev/null || echo none)"
exit 0
