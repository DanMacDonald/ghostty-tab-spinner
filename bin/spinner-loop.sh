#!/usr/bin/env bash
# OSC 0 spinner:
#   normal: braille + project label
#   alert:  [!] / [.] + "Action Required"
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

should_run || exit 0

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
  ALERT_ARGS=(--alert)
else
  flag="$(busy_flag)"
  [[ -f "$flag" ]] || exit 0
  # Don't start braille if alert owns the tab.
  [[ -f "$(alert_flag)" ]] && exit 0
  LABEL="$(spin_label)"
  IDLE="$(idle_title)"
  INTERVAL_MS="$(python3 -c "print(int(float('$(spinner_interval_sec)')*1000))" 2>/dev/null || echo 100)"
  PF="$(pid_file)"
  ALERT_ARGS=()
fi

TTY_PATH="$(resolve_tty 2>/dev/null || true)"
if [[ -z "${TTY_PATH:-}" ]]; then
  hook_log "spinner-loop: no tty"
  exit 0
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN_PATH="$HERE/gts-title"

hook_log "spinner-loop mode=$([[ $ALERT_MODE == 1 ]] && echo alert || echo busy) label=${LABEL} tty=${TTY_PATH} ms=${INTERVAL_MS}"

if [[ -x "$BIN_PATH" ]]; then
  if [[ "$ALERT_MODE" == "1" ]]; then
    exec "$BIN_PATH" spin \
      --tty "$TTY_PATH" \
      --label "$LABEL" \
      --flag "$flag" \
      --interval-ms "$INTERVAL_MS" \
      --idle "$IDLE" \
      --pid-file "$PF" \
      --last-title-file "$(last_title_file)" \
      --alert
  elif [[ "${GHOSTTY_TAB_SPINNER_ASCII:-0}" == "1" ]]; then
    exec "$BIN_PATH" spin \
      --tty "$TTY_PATH" \
      --label "$LABEL" \
      --flag "$flag" \
      --interval-ms "$INTERVAL_MS" \
      --idle "$IDLE" \
      --pid-file "$PF" \
      --last-title-file "$(last_title_file)" \
      --ascii
  else
    exec "$BIN_PATH" spin \
      --tty "$TTY_PATH" \
      --label "$LABEL" \
      --flag "$flag" \
      --interval-ms "$INTERVAL_MS" \
      --idle "$IDLE" \
      --pid-file "$PF" \
      --last-title-file "$(last_title_file)"
  fi
fi

# Bash fallback
if [[ "$ALERT_MODE" == "1" ]]; then
  frames=("[!]" "[.]")
else
  frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
fi
i=0
while [[ -f "$flag" ]]; do
  write_tty "$(printf '\033]0;%s %s\007' "${frames[i]}" "$LABEL")"
  i=$(( (i + 1) % ${#frames[@]} ))
  if [[ "$ALERT_MODE" == "1" ]]; then
    sleep "${GHOSTTY_TAB_SPINNER_INTERVAL:-0.5}"
  else
    sleep "$(spinner_interval_sec)"
  fi
done
write_tty "$(printf '\033]0;%s\007' "$IDLE")"
