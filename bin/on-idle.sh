#!/usr/bin/env bash
# Agent turn ended (Stop / StopFailure) — stop spinner immediately.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
set +e

hook_log "on-idle enter event=${GROK_HOOK_EVENT:-?} session=${GROK_SESSION_ID:-?}"

should_run || exit 0

case "${GROK_HOOK_EVENT:-}" in
  stop|stop_failure|session_end|Stop|StopFailure|SessionEnd|""|cancel|cancelled|interrupted|abort)
    ;;
  *)
    ev="$(printf '%s' "${GROK_HOOK_EVENT:-}" | tr '[:upper:]' '[:lower:]')"
    case "$ev" in
      *stop*|*cancel*|*interrupt*|*abort*) ;;
      *)
        hook_log "on-idle ignore event=${GROK_HOOK_EVENT:-}"
        exit 0
        ;;
    esac
    ;;
esac

cancel_idle_grace 2>/dev/null || true
stop_alert_loop 0 2>/dev/null || true
stop_spinner_loop 2>/dev/null || true
sleep 0.05 2>/dev/null

idle="$(idle_title)"
for _ in 1 2 3; do
  set_title_osc "$idle" 2>/dev/null || true
  sleep 0.03 2>/dev/null
done

hook_log "on-idle done restored=${idle}"
exit 0
