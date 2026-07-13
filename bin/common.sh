#!/usr/bin/env bash
# ghostty-tab-spinner — shared helpers for hook scripts.
#
# Titles:
#   idle:  {project}   or  {project} - Grok  (if basename collides)
#   busy:  ⠋ {project}
#   alert: [!] Action Required  ↔  [.] Action Required
#
# Pure OSC to the session PTY. No AppleScript.
#
# IMPORTANT: when sourced by hooks, do NOT enable `set -e` — hooks must
# fail open so a spinner glitch never blocks tools.
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  set -euo pipefail
else
  set +e
  set -u 2>/dev/null || true
fi

_GTS_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# --- Paths ------------------------------------------------------------------

plugin_root() {
  echo "${GROK_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$_GTS_BIN_DIR/..}}"
}

plugin_data() {
  if [[ -n "${GROK_PLUGIN_DATA:-}" ]]; then
    mkdir -p "$GROK_PLUGIN_DATA"
    echo "$GROK_PLUGIN_DATA"
    return
  fi
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    mkdir -p "$CLAUDE_PLUGIN_DATA"
    echo "$CLAUDE_PLUGIN_DATA"
    return
  fi
  # Global-hooks install has no GROK_PLUGIN_DATA — fall back to TMPDIR.
  local d="${TMPDIR:-/tmp}/ghostty-tab-spinner/${GROK_SESSION_ID:-default}"
  mkdir -p "$d"
  echo "$d"
}

session_dir() {
  local sid="${GROK_SESSION_ID:-default}"
  sid="${sid//\//_}"
  local d
  d="$(plugin_data)/sessions/${sid}"
  mkdir -p "$d"
  echo "$d"
}

busy_flag() { echo "$(session_dir)/busy.flag"; }
pid_file() { echo "$(session_dir)/spinner.pid"; }
alert_flag() { echo "$(session_dir)/alert.flag"; }
alert_pid_file() { echo "$(session_dir)/alert.pid"; }
last_title_file() { echo "$(session_dir)/last_title.txt"; }

hook_log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$(session_dir)/hook.log" 2>/dev/null || true
  [[ "${GHOSTTY_TAB_SPINNER_DEBUG:-}" == "1" ]] && printf '[gts] %s\n' "$*" >&2
  return 0
}

spinner_interval_sec() {
  echo "${GHOSTTY_TAB_SPINNER_INTERVAL:-0.1}"
}

alert_title() {
  echo "${GHOSTTY_TAB_SPINNER_ALERT_TITLE:-Action Required}"
}

# --- Titles -----------------------------------------------------------------

project_basename() {
  local root="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-${PWD:-}}}"
  if [[ -n "$root" && "$root" != "/" ]]; then
    basename "$root"
  else
    echo "terminal"
  fi
}

# True if >=2 live Grok sessions share this project basename.
project_name_collides() {
  local label="$1"
  local f="${HOME}/.grok/active_sessions.json"
  [[ -f "$f" ]] || return 1
  python3 - "$f" "$label" <<'PY' 2>/dev/null
import json, os, sys
from pathlib import Path

path, label = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(1)
if not isinstance(data, list):
    sys.exit(1)

def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False

count = 0
for row in data:
    if not alive(row.get("pid")):
        continue
    cwd = row.get("cwd") or row.get("workspace") or ""
    if cwd and Path(cwd).name == label:
        count += 1

sys.exit(0 if count >= 2 else 1)
PY
}

tab_label() {
  local base
  base="$(project_basename)"
  if [[ -n "${GHOSTTY_TAB_SPINNER_FORCE_DISAMBIG:-}" ]] || project_name_collides "$base"; then
    printf '%s - Grok' "$base"
  else
    printf '%s' "$base"
  fi
}

idle_title() { tab_label; }
spin_label() { tab_label; }

# --- TTY discovery ----------------------------------------------------------

normalize_tty_name() {
  local name="${1// /}"
  [[ -z "$name" || "$name" == "??" || "$name" == "?" || "$name" == "-" ]] && return 1
  if [[ "$name" == /dev/* ]]; then
    [[ -e "$name" && -w "$name" ]] || return 1
    [[ "$name" == "/dev/tty" ]] && return 1
    echo "$name"
    return 0
  fi
  local path="/dev/${name}"
  [[ -e "$path" && -w "$path" ]] || return 1
  echo "$path"
}

discover_tty_from_active_session() {
  local sid="${GROK_SESSION_ID:-}" pid path
  local f="${HOME}/.grok/active_sessions.json"
  [[ -z "$sid" || "$sid" == "default" || ! -f "$f" ]] && return 1
  pid="$(python3 - "$f" "$sid" <<'PY' 2>/dev/null || true
import json, sys
data = json.load(open(sys.argv[1]))
sid = sys.argv[2]
for row in data if isinstance(data, list) else []:
    if str(row.get("session_id", "")) == sid:
        print(row.get("pid", ""))
        raise SystemExit(0)
raise SystemExit(1)
PY
)"
  [[ -z "$pid" ]] && return 1
  path="$(ps -p "$pid" -o tty= 2>/dev/null | tr -d '[:space:]' || true)"
  normalize_tty_name "$path" 2>/dev/null
}

discover_tty_from_process_tree() {
  local pid="${1:-$$}" i tty_name path ppid
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    tty_name="$(ps -p "$pid" -o tty= 2>/dev/null | tr -d '[:space:]' || true)"
    if path="$(normalize_tty_name "$tty_name" 2>/dev/null)"; then
      echo "$path"
      return 0
    fi
    ppid="$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]' || true)"
    [[ -z "$ppid" || "$ppid" == "0" || "$ppid" == "1" || "$ppid" == "$pid" ]] && break
    pid="$ppid"
  done
  return 1
}

capture_tty() {
  local sd path t
  sd="$(session_dir)"
  if [[ -f "$sd/tty" ]]; then
    t="$(cat "$sd/tty" 2>/dev/null || true)"
    if path="$(normalize_tty_name "$t" 2>/dev/null)"; then
      echo "$path" >"$sd/tty"
      echo "$path"
      return 0
    fi
  fi
  if [[ -n "${GROK_TTY:-}" ]] && path="$(normalize_tty_name "${GROK_TTY}" 2>/dev/null)"; then
    echo "$path" >"$sd/tty"
    echo "$path"
    return 0
  fi
  if path="$(discover_tty_from_active_session 2>/dev/null)"; then
    echo "$path" >"$sd/tty"
    hook_log "tty via active_sessions: $path"
    echo "$path"
    return 0
  fi
  if t="$(tty 2>/dev/null)" && path="$(normalize_tty_name "$t" 2>/dev/null)"; then
    echo "$path" >"$sd/tty"
    echo "$path"
    return 0
  fi
  if path="$(discover_tty_from_process_tree "$$" 2>/dev/null)"; then
    echo "$path" >"$sd/tty"
    hook_log "tty via process tree: $path"
    echo "$path"
    return 0
  fi
  hook_log "failed to capture pty"
  return 1
}

resolve_tty() {
  local sd t path
  sd="$(session_dir)"
  if [[ -f "$sd/tty" ]]; then
    t="$(cat "$sd/tty" 2>/dev/null || true)"
    if path="$(normalize_tty_name "$t" 2>/dev/null)"; then
      echo "$path"
      return 0
    fi
  fi
  capture_tty
}

write_tty() {
  local data="$1" tty_path
  tty_path="$(resolve_tty 2>/dev/null)" || return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import os, sys
path, data = sys.argv[1], sys.argv[2].encode("utf-8")
fd = os.open(path, os.O_WRONLY | os.O_NOCTTY)
try:
    os.write(fd, data)
finally:
    os.close(fd)
' "$tty_path" "$data" 2>/dev/null || true
  else
    printf '%s' "$data" >"$tty_path" 2>/dev/null || true
  fi
}

# --- OSC titles -------------------------------------------------------------

set_title_osc() {
  local title="$1"
  # OSC 0 (icon+window) + OSC 2 (window). Prefer raw PTY write — gts-title set
  # has hung under hook timeouts.
  write_tty "$(printf '\033]0;%s\007\033]2;%s\007' "$title" "$title")"
  return 0
}

# --- Process lifecycle ------------------------------------------------------

# hard=1 → SIGKILL only (skip gts-title SIGTERM idle-restore when switching modes).
_kill_pidfile() {
  local pf="$1" hard="${2:-0}" pid waited
  [[ -f "$pf" ]] || return 0
  pid="$(cat "$pf" 2>/dev/null || true)"
  if [[ -n "$pid" && "$pid" != "$$" ]]; then
    if [[ "$hard" == "1" ]]; then
      kill -9 "$pid" 2>/dev/null || true
    else
      kill -TERM "$pid" 2>/dev/null || true
      waited=0
      while [[ $waited -lt 15 ]]; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1 2>/dev/null || true
        waited=$((waited + 1))
      done
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pf" 2>/dev/null || true
}

spinner_is_healthy() {
  local pf old
  pf="$(pid_file)"
  [[ -f "$(busy_flag)" ]] || return 1
  [[ -f "$(alert_flag)" ]] && return 1
  [[ -f "$pf" ]] || return 1
  old="$(cat "$pf" 2>/dev/null || true)"
  [[ -n "$old" ]] || return 1
  kill -0 "$old" 2>/dev/null || return 1
}

alert_is_healthy() {
  local pf old
  pf="$(alert_pid_file)"
  [[ -f "$(alert_flag)" ]] || return 1
  [[ -f "$pf" ]] || return 1
  old="$(cat "$pf" 2>/dev/null || true)"
  [[ -n "$old" ]] || return 1
  kill -0 "$old" 2>/dev/null || return 1
}

_export_runtime_env() {
  export GROK_SESSION_ID="${GROK_SESSION_ID:-default}"
  export GROK_PLUGIN_DATA="${GROK_PLUGIN_DATA:-$(plugin_data)}"
  export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(plugin_root)}"
  export GROK_WORKSPACE_ROOT="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-${PWD:-}}}"
  export GHOSTTY_TAB_SPINNER_DEBUG="${GHOSTTY_TAB_SPINNER_DEBUG:-}"
}

ensure_spinner_loop() {
  local pf loop old
  [[ -f "$(alert_flag)" ]] && return 0
  touch "$(busy_flag)" 2>/dev/null || true

  if spinner_is_healthy; then
    hook_log "spinner healthy pid=$(cat "$(pid_file)")"
    return 0
  fi

  pf="$(pid_file)"
  if [[ -f "$pf" ]]; then
    old="$(cat "$pf" 2>/dev/null || true)"
    if [[ -n "$old" ]] && ! kill -0 "$old" 2>/dev/null; then
      rm -f "$pf" 2>/dev/null || true
    elif [[ -n "$old" ]]; then
      kill -9 "$old" 2>/dev/null || true
      rm -f "$pf" 2>/dev/null || true
    fi
  fi

  _export_runtime_env
  export GHOSTTY_TAB_SPINNER_INTERVAL="${GHOSTTY_TAB_SPINNER_INTERVAL:-}"
  export GHOSTTY_TAB_SPINNER_ASCII="${GHOSTTY_TAB_SPINNER_ASCII:-}"
  unset GHOSTTY_TAB_SPINNER_ALERT 2>/dev/null || true

  loop="$_GTS_BIN_DIR/spinner-loop.sh"
  [[ -f "$loop" ]] || { hook_log "ensure_spinner FAIL no loop at $loop"; return 1; }
  nohup bash "$loop" </dev/null >>"$(session_dir)/spinner.stderr" 2>&1 &
  echo $! >"$pf"
  disown 2>/dev/null || true
  hook_log "started spinner pid=$(cat "$pf") label=$(spin_label)"
}

start_alert_loop() {
  local pf loop title
  title="$(alert_title)"
  capture_tty >/dev/null 2>&1 || true

  if alert_is_healthy; then
    hook_log "alert already healthy pid=$(cat "$(alert_pid_file)")"
    return 0
  fi

  _kill_pidfile "$(pid_file)" 1
  rm -f "$(busy_flag)" 2>/dev/null || true
  touch "$(alert_flag)" 2>/dev/null || true
  pf="$(alert_pid_file)"
  rm -f "$pf" 2>/dev/null || true

  _export_runtime_env
  export GHOSTTY_TAB_SPINNER_ALERT=1
  export GHOSTTY_TAB_SPINNER_ALERT_TITLE="$title"
  export GHOSTTY_TAB_SPINNER_INTERVAL="${GHOSTTY_TAB_SPINNER_ALERT_INTERVAL:-0.5}"

  set_title_osc "[!] ${title}" || true

  loop="$_GTS_BIN_DIR/spinner-loop.sh"
  nohup bash "$loop" </dev/null >>"$(session_dir)/alert.stderr" 2>&1 &
  echo $! >"$pf"
  disown 2>/dev/null || true
  hook_log "started alert pid=$(cat "$pf") title=${title}"
}

stop_alert_loop() {
  local restore_idle="${1:-0}"
  rm -f "$(alert_flag)" 2>/dev/null || true
  _kill_pidfile "$(alert_pid_file)" 1
  if [[ "$restore_idle" == "1" ]]; then
    set_title_osc "$(idle_title)" || true
  fi
  return 0
}

stop_spinner_loop() {
  rm -f "$(busy_flag)" 2>/dev/null || true
  _kill_pidfile "$(pid_file)" 1
  return 0
}

# --- Hook payload helpers ---------------------------------------------------

is_action_required_notification() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    permission_prompt|permission|permissionrequest|permission_request) return 0 ;;
    agent_needs_input|needs_input|user_input|elicitation_dialog|elicitation) return 0 ;;
    ask_user|ask_user_question|confirmation|confirm|prompt) return 0 ;;
    *permission*|*needs_input*|*elicitation*|*ask_user*) return 0 ;;
    idle_prompt|auth_success|agent_completed|elicitation_complete|elicitation_response) return 1 ;;
    *) return 1 ;;
  esac
}

is_user_input_tool() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    ask_user_question|askuserquestion|ask_user|askuser) return 0 ;;
    *ask_user*|*askuser*) return 0 ;;
    *) return 1 ;;
  esac
}

read_hook_tool_name() {
  local payload="${1-}"
  if [[ -z "$payload" ]] && [[ ! -t 0 ]]; then
    payload="$(cat 2>/dev/null || true)"
  fi
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
for key in ("toolName", "tool_name", "tool", "name"):
    v = data.get(key)
    if isinstance(v, str) and v.strip():
        print(v.strip())
        raise SystemExit(0)
' 2>/dev/null || true
}
