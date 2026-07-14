#!/usr/bin/env bash
# Stop / StopFailure — restore idle project title.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
set +e

hook_log "on-idle enter event=${GROK_HOOK_EVENT:-?} session=${GROK_SESSION_ID:-?}"
go_idle 2>/dev/null || true
hook_log "on-idle done"
exit 0
