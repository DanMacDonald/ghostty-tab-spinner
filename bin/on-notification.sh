#!/usr/bin/env bash
# Notification: permission / elicitation → Action Required pulse.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

payload=""
[[ ! -t 0 ]] && payload="$(cat 2>/dev/null || true)"

ntype="$(
  printf '%s' "$payload" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(0)
if not isinstance(data, dict):
    raise SystemExit(0)
for key in ("notificationType", "notification_type", "type", "notification", "kind", "name", "event"):
    v = data.get(key)
    if isinstance(v, str) and v.strip():
        print(v.strip())
        raise SystemExit(0)
for nest in ("notification", "data", "payload"):
    n = data.get(nest)
    if isinstance(n, dict):
        for key in ("type", "notification_type", "notificationType", "kind"):
            v = n.get(key)
            if isinstance(v, str) and v.strip():
                print(v.strip())
                raise SystemExit(0)
' 2>/dev/null || true
)"

[[ -z "$ntype" ]] && ntype="${GROK_NOTIFICATION_TYPE:-${CLAUDE_NOTIFICATION_TYPE:-}}"
[[ -z "$ntype" ]] && ntype="${GROK_HOOK_MATCHER:-}"

hook_log "on-notification type=${ntype:-?} event=${GROK_HOOK_EVENT:-?}"

if [[ -z "$ntype" ]]; then
  if printf '%s' "$payload" | grep -Eiq 'permission|approve|confirm|waiting for|needs? (your )?input|action required'; then
    start_alert_loop || true
  fi
  exit 0
fi

if is_action_required_notification "$ntype"; then
  start_alert_loop || true
fi
exit 0
