#!/usr/bin/env bash
# Notification hook: when Grok needs user input, show Codex-style
#   [!] Action Required  ↔  [.] Action Required
# Only for real "please respond" notifications — not idle_prompt after a turn.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

# Read hook JSON from stdin (best-effort).
payload=""
if [[ ! -t 0 ]]; then
  payload="$(cat 2>/dev/null || true)"
fi

# Always log raw payload for discovery (truncated).
if [[ -n "$payload" ]]; then
  printf '%s\n' "$payload" | head -c 4000 >>"$(session_dir)/notification.jsonl" 2>/dev/null || true
  echo >>"$(session_dir)/notification.jsonl" 2>/dev/null || true
fi

ntype="$(
  printf '%s' "$payload" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
try:
    data = json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)
if not isinstance(data, dict):
    print("")
    raise SystemExit(0)
for key in (
    "notificationType", "notification_type", "type",
    "notification", "kind", "name", "event",
):
    v = data.get(key)
    if isinstance(v, str) and v.strip():
        print(v.strip())
        raise SystemExit(0)
# Nested
for nest in ("notification", "data", "payload"):
    n = data.get(nest)
    if isinstance(n, dict):
        for key in ("type", "notification_type", "notificationType", "kind"):
            v = n.get(key)
            if isinstance(v, str) and v.strip():
                print(v.strip())
                raise SystemExit(0)
# Message heuristics
msg = str(data.get("message") or data.get("title") or data.get("content") or "")
print("")
' 2>/dev/null || true
)"

# Also accept matcher / env if Grok sets them.
[[ -z "$ntype" ]] && ntype="${GROK_NOTIFICATION_TYPE:-${CLAUDE_NOTIFICATION_TYPE:-}}"
[[ -z "$ntype" ]] && ntype="${GROK_HOOK_MATCHER:-}"

hook_log "on-notification type=${ntype:-?} event=${GROK_HOOK_EVENT:-?} payload_bytes=${#payload}"

if ! should_run; then
  exit 0
fi

if [[ -z "$ntype" ]]; then
  # Unknown shape: if message clearly asks for permission, still alert.
  if printf '%s' "$payload" | grep -Eiq 'permission|approve|confirm|waiting for|needs? (your )?input|action required'; then
    hook_log "on-notification heuristic match → alert"
    start_alert_loop || true
  else
    hook_log "on-notification ignored (no type)"
  fi
  exit 0
fi

if is_action_required_notification "$ntype"; then
  start_alert_loop || true
else
  hook_log "on-notification not action-required type=${ntype}"
fi
exit 0
