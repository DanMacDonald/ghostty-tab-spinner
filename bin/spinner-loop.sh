#!/usr/bin/env bash
# Background OSC spinner (braille or Action Required). Prefer gts-title.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

ALERT_MODE=0
if [[ "${GHOSTTY_TAB_SPINNER_ALERT:-0}" == "1" ]] || [[ -f "$(alert_flag)" && ! -f "$(busy_flag)" ]]; then
  if [[ -f "$(alert_flag)" ]] || [[ "${GHOSTTY_TAB_SPINNER_ALERT:-0}" == "1" ]]; then
    ALERT_MODE=1
  fi
fi

if [[ "$ALERT_MODE" == "1" ]]; then
  flag="$(alert_flag)"
  [[ -f "$flag" ]] || exit 0
  LABEL="$(alert_title)"
  IDLE="$(idle_title)"
  INTERVAL_MS="$(python3 -c "print(int(float('${GHOSTTY_TAB_SPINNER_INTERVAL:-0.5}')*1000))" 2>/dev/null || echo 500)"
  PF="$(alert_pid_file)"
else
  flag="$(busy_flag)"
  [[ -f "$flag" ]] || exit 0
  [[ -f "$(alert_flag)" ]] && exit 0
  LABEL="$(spin_label)"
  IDLE="$(idle_title)"
  INTERVAL_MS="$(python3 -c "print(int(float('$(spinner_interval_sec)')*1000))" 2>/dev/null || echo 100)"
  PF="$(pid_file)"
fi

TTY_PATH="$(resolve_tty 2>/dev/null || true)"
if [[ -z "${TTY_PATH:-}" ]]; then
  hook_log "spinner-loop: no tty"
  exit 0
fi

BIN_PATH="$(cd "$(dirname "$0")" && pwd)/gts-title"
# Prefer path resolved by ensure_spinner_loop; fall back to live discovery.
EVENTS_FILE="${GHOSTTY_TAB_SPINNER_EVENTS_FILE:-}"
if [[ -z "$EVENTS_FILE" || ! -f "$EVENTS_FILE" ]]; then
  EVENTS_FILE="$(events_jsonl 2>/dev/null || true)"
fi
hook_log "spinner-loop mode=$([[ $ALERT_MODE == 1 ]] && echo alert || echo busy) label=${LABEL} tty=${TTY_PATH} ms=${INTERVAL_MS} events=${EVENTS_FILE:-none}"

if [[ -x "$BIN_PATH" ]]; then
  args=(spin --tty "$TTY_PATH" --label "$LABEL" --flag "$flag" --interval-ms "$INTERVAL_MS" --idle "$IDLE" --pid-file "$PF" --last-title-file "$(last_title_file)")
  if [[ -n "${EVENTS_FILE:-}" ]]; then
    args+=(--events-file "$EVENTS_FILE")
  fi
  if [[ "$ALERT_MODE" == "1" ]]; then
    args+=(--alert)
  elif [[ "${GHOSTTY_TAB_SPINNER_ASCII:-0}" == "1" ]]; then
    args+=(--ascii)
  fi
  exec "$BIN_PATH" "${args[@]}"
fi

# Bash fallback when gts-title is missing
if [[ "$ALERT_MODE" == "1" ]]; then
  frames=("[!]" "[.]")
else
  frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
fi
# Seek to EOF so we only react to turn_ended written after spin start (Ctrl-C, complete).
EVENTS_OFF=0
if [[ -n "${EVENTS_FILE:-}" && -f "$EVENTS_FILE" ]]; then
  EVENTS_OFF="$(wc -c <"$EVENTS_FILE" 2>/dev/null | tr -d ' ' || echo 0)"
fi
i=0
while [[ -f "$flag" ]]; do
  if [[ -n "${EVENTS_FILE:-}" ]]; then
    if new_off="$(events_saw_turn_ended "$EVENTS_FILE" "$EVENTS_OFF")"; then
      hook_log "spinner-loop: turn_ended in events.jsonl — clearing"
      rm -f "$flag" "$(busy_flag)" "$(alert_flag)" 2>/dev/null || true
      break
    fi
    EVENTS_OFF="${new_off:-$EVENTS_OFF}"
  fi
  write_tty "$(printf '\033]0;%s %s\007\033]2;%s %s\007' "${frames[i]}" "$LABEL" "${frames[i]}" "$LABEL")"
  i=$(( (i + 1) % ${#frames[@]} ))
  if [[ "$ALERT_MODE" == "1" ]]; then
    sleep "${GHOSTTY_TAB_SPINNER_INTERVAL:-0.5}"
  else
    sleep "$(spinner_interval_sec)"
  fi
done
write_tty "$(printf '\033]0;%s\007\033]2;%s\007' "$IDLE" "$IDLE")"
