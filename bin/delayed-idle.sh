#!/usr/bin/env bash
# Wait out TUI "Responding..." lag, then stop spinner if still the pending idle.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

token="${GHOSTTY_TAB_SPINNER_IDLE_TOKEN:-}"
grace="${GHOSTTY_TAB_SPINNER_IDLE_GRACE:-$(idle_grace_sec)}"

hook_log "delayed-idle sleep ${grace}s token=${token}"

# Slice sleep so cancel is noticed reasonably fast.
left="$grace"
while awk "BEGIN{exit !($left > 0)}"; do
  # Token cleared/changed → cancelled.
  cur="$(cat "$(idle_token_file)" 2>/dev/null || true)"
  if [[ -z "$token" || "$cur" != "$token" ]]; then
    hook_log "delayed-idle cancelled (token mismatch)"
    exit 0
  fi
  # New busy turn already cleared busy? keep waiting only if spinner still wanted.
  slice="0.2"
  if awk "BEGIN{exit !($left < 0.2)}"; then
    slice="$left"
  fi
  sleep "$slice" 2>/dev/null || sleep 1
  left="$(awk -v l="$left" -v s="$slice" 'BEGIN{printf "%.2f", (l>s?l-s:0)}')"
done

cur="$(cat "$(idle_token_file)" 2>/dev/null || true)"
if [[ -z "$token" || "$cur" != "$token" ]]; then
  hook_log "delayed-idle cancelled after wait"
  exit 0
fi

hook_log "delayed-idle committing stop"
stop_spinner_loop
sleep 0.1 2>/dev/null

idle="$(idle_title)"
for _ in 1 2 3; do
  set_title_osc "$idle"
  sleep 0.05 2>/dev/null
done

rm -f "$(idle_token_file)" "$(idle_grace_pid_file)" 2>/dev/null
hook_log "delayed-idle done restored=${idle}"
exit 0
