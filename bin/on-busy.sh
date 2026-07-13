#!/usr/bin/env bash
# Agent turn started — start Codex-style tab spinner.
# Keep this hook FAST (<1s): UserPromptSubmit timeout is 5s.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
set +e

hook_log "on-busy enter event=${GROK_HOOK_EVENT:-?} session=${GROK_SESSION_ID:-?} label=$(spin_label)"

should_run || exit 0

# Capture tty quickly (non-fatal).
capture_tty >/dev/null 2>&1 || true

# Clear alert first (fast hard-kill), then start busy spinner.
cancel_idle_grace 2>/dev/null || true
stop_alert_loop 0 2>/dev/null || true

touch "$(busy_flag)" 2>/dev/null || true

if spinner_is_healthy; then
  hook_log "on-busy already healthy pid=$(cat "$(pid_file)" 2>/dev/null)"
  exit 0
fi

ensure_spinner_loop 2>/dev/null || true
# Best-effort first frame (non-blocking write_tty).
set_busy_indicator 2>/dev/null || true

hook_log "on-busy done pid=$(cat "$(pid_file)" 2>/dev/null || echo none) busy=$([[ -f $(busy_flag) ]] && echo Y || echo N)"
exit 0
