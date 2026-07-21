#!/usr/bin/env bash
# UserPromptSubmit — start braille tab spinner. Keep FAST (<1s).
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
set +e

hook_log "on-busy enter event=${GROK_HOOK_EVENT:-?} session=${GROK_SESSION_ID:-?} label=$(spin_label)"

capture_tty >/dev/null 2>&1 || true
stop_alert_loop 0 2>/dev/null || true
touch "$(busy_flag)" 2>/dev/null || true

if spinner_is_healthy; then
  hook_log "on-busy already healthy pid=$(cat "$(pid_file)" 2>/dev/null)"
  exit 0
fi

ensure_spinner_loop 2>/dev/null || true
# Under Herdr: static busy title (sidebar re-renders on every OSC change).
# Outside Herdr: first braille frame; the spinner loop animates the rest.
if in_herdr; then
  set_display_title "⠋ $(spin_label)" 2>/dev/null || true
else
  set_title_osc "⠋ $(spin_label)" 2>/dev/null || true
fi
hook_log "on-busy done pid=$(cat "$(pid_file)" 2>/dev/null || echo none) herdr=$(in_herdr && echo 1 || echo 0)"
exit 0
