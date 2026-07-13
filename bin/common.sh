#!/usr/bin/env bash
# ghostty-tab-spinner — Codex-style OSC 0 tab spinner.
#
# Titles:
#   idle:  {project}              or  {project} - Grok  (if name collides)
#   busy:  ⠋ {project}            or  ⠋ {project} - Grok
#
# Collision = another live Grok session with the same basename(cwd)
# (from ~/.grok/active_sessions.json). Cross-platform; no AppleScript.
#
# IMPORTANT: when this file is *sourced* by hooks, do NOT enable `set -e`.
# Hooks intentionally ignore failures; `set -e` was aborting on-busy/on-activity
# before the spinner could start (user saw no tab animation).
if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
  set -euo pipefail
else
  set +e
  set -u 2>/dev/null || true
fi

# Fixed at source time — BASH_SOURCE is unreliable inside functions under `set -u`.
_GTS_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

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
activity_file() { echo "$(session_dir)/activity.txt"; }
last_title_file() { echo "$(session_dir)/last_title.txt"; }
idle_token_file() { echo "$(session_dir)/idle_token"; }
idle_grace_pid_file() { echo "$(session_dir)/idle_grace.pid"; }
alert_flag() { echo "$(session_dir)/alert.flag"; }
alert_pid_file() { echo "$(session_dir)/alert.pid"; }

# Tab title while waiting for the user (permission / question / build prompt).
alert_title() {
  echo "${GHOSTTY_TAB_SPINNER_ALERT_TITLE:-Action Required}"
}

# Optional delay after Stop before clearing the tab spinner (seconds).
# Default 0: stop with the turn. There is no hook for TUI "Responding...".
# Only set >0 if you want a deliberate linger (not UI-synced).
idle_grace_sec() {
  echo "${GHOSTTY_TAB_SPINNER_IDLE_GRACE:-0}"
}

# Cancel a pending delayed-idle (new busy turn, or reschedule).
cancel_idle_grace() {
  local pf old
  pf="$(idle_grace_pid_file)"
  if [[ -f "$pf" ]]; then
    old="$(cat "$pf" 2>/dev/null || true)"
    if [[ -n "$old" && "$old" != "$$" ]]; then
      kill -TERM "$old" 2>/dev/null || true
    fi
    rm -f "$pf" 2>/dev/null || true
  fi
  rm -f "$(idle_token_file)" 2>/dev/null || true
}

# Optional delayed idle when GHOSTTY_TAB_SPINNER_IDLE_GRACE > 0.
schedule_idle_grace() {
  local token grace script
  grace="$(idle_grace_sec)"
  # Treat empty/0 as immediate (caller should stop directly).
  if [[ -z "$grace" || "$grace" == "0" || "$grace" == "0.0" ]]; then
    return 1
  fi
  cancel_idle_grace
  token="$(date +%s)-${RANDOM}-$$"
  printf '%s' "$token" >"$(idle_token_file)"
  script="$_GTS_BIN_DIR/delayed-idle.sh"

  export GROK_SESSION_ID="${GROK_SESSION_ID:-default}"
  export GROK_PLUGIN_DATA="${GROK_PLUGIN_DATA:-$(plugin_data)}"
  export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(plugin_root)}"
  export GROK_WORKSPACE_ROOT="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-${PWD:-}}}"
  export GHOSTTY_TAB_SPINNER_FORCE="${GHOSTTY_TAB_SPINNER_FORCE:-1}"
  export GHOSTTY_TAB_SPINNER_DEBUG="${GHOSTTY_TAB_SPINNER_DEBUG:-}"
  export GHOSTTY_TAB_SPINNER_IDLE_TOKEN="$token"
  export GHOSTTY_TAB_SPINNER_IDLE_GRACE="$grace"

  nohup bash "$script" </dev/null >>"$(session_dir)/idle_grace.stderr" 2>&1 &
  echo $! >"$(idle_grace_pid_file)"
  disown 2>/dev/null || true
  hook_log "scheduled idle grace ${grace}s token=${token} pid=$(cat "$(idle_grace_pid_file)")"
}

hook_log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$(session_dir)/hook.log" 2>/dev/null || true
  [[ "${GHOSTTY_TAB_SPINNER_DEBUG:-}" == "1" ]] && printf '[gts] %s\n' "$*" >&2
  return 0
}

# Always try — hooks have no TTY; FORCE/env is optional.
should_run() {
  return 0
}

indicator_mode() {
  echo "${GHOSTTY_TAB_SPINNER_MODE:-title}"
}

spinner_interval_sec() {
  echo "${GHOSTTY_TAB_SPINNER_INTERVAL:-0.1}"
}

# --- Titles (Codex-style) ---------------------------------------------------

# Project folder name only.
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
    if not cwd:
        continue
    if Path(cwd).name == label:
        count += 1

sys.exit(0 if count >= 2 else 1)
PY
}

# Codex label; append " - Grok" only when the project name collides.
tab_label() {
  local base
  base="$(project_basename)"
  if [[ -n "${GHOSTTY_TAB_SPINNER_FORCE_DISAMBIG:-}" ]] || project_name_collides "$base"; then
    printf '%s - Grok' "$base"
  else
    printf '%s' "$base"
  fi
}

spin_label() { tab_label; }
idle_title() { tab_label; }

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

discover_tty_from_grok_processes() {
  local line gtty path
  while IFS= read -r line; do
    gtty="$(printf '%s' "$line" | awk '{print $2}')"
    if path="$(normalize_tty_name "$gtty" 2>/dev/null)"; then
      echo "$path"
      return 0
    fi
  done < <(ps -axo pid=,tty=,command= 2>/dev/null | grep -E '(^|/)grok( |$)' | grep -v grep || true)
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
  if path="$(discover_tty_from_grok_processes 2>/dev/null)"; then
    echo "$path" >"$sd/tty"
    hook_log "tty via grok scan: $path"
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

gts_title_bin() {
  local here="$_GTS_BIN_DIR"
  if [[ -x "$here/gts-title" ]]; then
    echo "$here/gts-title"
    return 0
  fi
  if [[ -x "$here/../rust/target/release/gts-title" ]]; then
    echo "$here/../rust/target/release/gts-title"
    return 0
  fi
  return 1
}

set_title_osc() {
  local title="$1"
  # Prefer direct PTY write — `gts-title set` has hung/been killed under hook
  # timeouts and blocked on-busy before the spinner could start.
  write_tty "$(printf '\033]0;%s\007' "$title")"
  [[ "${GHOSTTY_TAB_SPINNER_DEBUG:-}" == "1" ]] && hook_log "set_title_osc: $title"
  return 0
}

set_title() { set_title_osc "$1"; }

set_busy_indicator() {
  local mode label
  mode="$(indicator_mode)"
  label="$(spin_label)"
  case "$mode" in
    progress) ;;
    both)
      set_title_osc "⠋ ${label}" || true
      ;;
    *)
      set_title_osc "⠋ ${label}" || true
      ;;
  esac
}

set_idle_indicator() {
  set_title_osc "$(idle_title)" || true
}

# --- Spinner lifecycle ------------------------------------------------------

# Kill process from a pidfile.
# hard=1 → SIGKILL only (skip gts-title's SIGTERM idle-title restore — needed when
# switching braille → Action Required, otherwise the tab snaps back to project name).
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
  # Alert mode owns the tab — don't treat braille as healthy.
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

ensure_spinner_loop() {
  local mode pf loop
  mode="$(indicator_mode)"
  if [[ "$mode" != "title" && "$mode" != "both" ]]; then
    hook_log "ensure_spinner skip mode=${mode}"
    return 0
  fi
  [[ "${GHOSTTY_TAB_SPINNER_TITLE_LOOP:-1}" == "0" ]] && return 0
  # Don't fight Action Required alert.
  if [[ -f "$(alert_flag)" ]]; then
    hook_log "ensure_spinner skip (alert active)"
    return 0
  fi

  # Ensure busy flag exists so spinner-loop does not exit immediately.
  touch "$(busy_flag)" 2>/dev/null || true

  if spinner_is_healthy; then
    hook_log "spinner healthy pid=$(cat "$(pid_file)")"
    return 0
  fi

  pf="$(pid_file)"
  # Drop stale pid without waiting (dead process).
  if [[ -f "$pf" ]]; then
    local old
    old="$(cat "$pf" 2>/dev/null || true)"
    if [[ -n "$old" ]] && ! kill -0 "$old" 2>/dev/null; then
      rm -f "$pf" 2>/dev/null || true
    elif [[ -n "$old" ]]; then
      # Stale healthy check failed for other reasons — hard replace.
      kill -9 "$old" 2>/dev/null || true
      rm -f "$pf" 2>/dev/null || true
    fi
  fi

  export GROK_SESSION_ID="${GROK_SESSION_ID:-default}"
  export GROK_PLUGIN_DATA="${GROK_PLUGIN_DATA:-$(plugin_data)}"
  export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(plugin_root)}"
  export GROK_WORKSPACE_ROOT="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-${PWD:-}}}"
  export GHOSTTY_TAB_SPINNER_FORCE="${GHOSTTY_TAB_SPINNER_FORCE:-1}"
  export GHOSTTY_TAB_SPINNER_MODE="${GHOSTTY_TAB_SPINNER_MODE:-title}"
  export GHOSTTY_TAB_SPINNER_INTERVAL="${GHOSTTY_TAB_SPINNER_INTERVAL:-}"
  export GHOSTTY_TAB_SPINNER_ASCII="${GHOSTTY_TAB_SPINNER_ASCII:-}"
  export GHOSTTY_TAB_SPINNER_DEBUG="${GHOSTTY_TAB_SPINNER_DEBUG:-}"
  unset GHOSTTY_TAB_SPINNER_ALERT 2>/dev/null || true

  loop="$_GTS_BIN_DIR/spinner-loop.sh"
  if [[ ! -x "$loop" && ! -f "$loop" ]]; then
    hook_log "ensure_spinner FAIL no loop at $loop"
    return 1
  fi
  nohup bash "$loop" </dev/null >>"$(session_dir)/spinner.stderr" 2>&1 &
  echo $! >"$pf"
  disown 2>/dev/null || true
  hook_log "started spinner pid=$(cat "$pf") label=$(spin_label) flag=$(busy_flag)"
}

# Codex-style attention title while waiting for user (permission / question).
# Tab shows:  [!] Action Required  ↔  [.] Action Required
start_alert_loop() {
  local pf loop title
  title="$(alert_title)"
  capture_tty >/dev/null 2>&1 || true

  if alert_is_healthy; then
    hook_log "alert already healthy pid=$(cat "$(alert_pid_file)")"
    return 0
  fi

  # Hard-kill braille so SIGTERM idle-restore does not snap tab back to project name.
  _kill_pidfile "$(pid_file)" 1
  rm -f "$(busy_flag)" 2>/dev/null || true

  touch "$(alert_flag)" 2>/dev/null || true
  pf="$(alert_pid_file)"
  rm -f "$pf" 2>/dev/null || true

  export GROK_SESSION_ID="${GROK_SESSION_ID:-default}"
  export GROK_PLUGIN_DATA="${GROK_PLUGIN_DATA:-$(plugin_data)}"
  export GROK_PLUGIN_ROOT="${GROK_PLUGIN_ROOT:-$(plugin_root)}"
  export GROK_WORKSPACE_ROOT="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-${PWD:-}}}"
  export GHOSTTY_TAB_SPINNER_FORCE="${GHOSTTY_TAB_SPINNER_FORCE:-1}"
  export GHOSTTY_TAB_SPINNER_DEBUG="${GHOSTTY_TAB_SPINNER_DEBUG:-}"
  export GHOSTTY_TAB_SPINNER_ALERT=1
  export GHOSTTY_TAB_SPINNER_ALERT_TITLE="$title"
  export GHOSTTY_TAB_SPINNER_INTERVAL="${GHOSTTY_TAB_SPINNER_ALERT_INTERVAL:-0.5}"

  # Immediate title (before loop) via raw OSC + gts-title.
  write_tty "$(printf '\033]0;%s\007' "[!] ${title}")" || true
  set_title_osc "[!] ${title}" || true

  loop="$_GTS_BIN_DIR/spinner-loop.sh"
  nohup bash "$loop" </dev/null >>"$(session_dir)/alert.stderr" 2>&1 &
  echo $! >"$pf"
  disown 2>/dev/null || true
  hook_log "started alert pid=$(cat "$pf") title=${title} tty=$(resolve_tty 2>/dev/null || echo none)"
}

# Stop alert title; optionally restore idle project name.
# Fast path only (pidfile) — full `ps` scans blew the 5s hook timeout and
# prevented on-busy from starting the spinner on some turns.
stop_alert_loop() {
  local restore_idle="${1:-0}"
  local pf
  pf="$(alert_pid_file)"
  rm -f "$(alert_flag)" 2>/dev/null || true
  _kill_pidfile "$pf" 1

  if [[ "$restore_idle" == "1" ]]; then
    set_title_osc "$(idle_title)" || true
  fi
  hook_log "stop_alert_loop restore_idle=${restore_idle}"
  return 0
}

# Stop braille spinner for *this* session only (pidfile only — keep it fast).
stop_spinner_loop() {
  local pf
  pf="$(pid_file)"
  rm -f "$(busy_flag)" "$(activity_file)" 2>/dev/null || true
  # Hard kill: avoid gts-title writing idle title mid-transition when caller
  # will set a new title immediately after.
  _kill_pidfile "$pf" 1
  hook_log "stop_spinner_loop done (session-local)"
  return 0
}

# True if notification type means "user must respond".
is_action_required_notification() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    permission_prompt|permission|permissionrequest|permission_request) return 0 ;;
    agent_needs_input|needs_input|user_input|elicitation_dialog|elicitation) return 0 ;;
    ask_user|ask_user_question|confirmation|confirm|prompt) return 0 ;;
    *permission*|*needs_input*|*elicitation*|*ask_user*) return 0 ;;
    # idle_prompt = waiting for next chat message after a turn — not mid-task action.
    idle_prompt|auth_success|agent_completed|elicitation_complete|elicitation_response) return 1 ;;
    *) return 1 ;;
  esac
}

# Tools that block on user input (PreToolUse should enter alert, not busy).
is_user_input_tool() {
  local t
  t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    ask_user_question|askuserquestion|ask_user|askuser) return 0 ;;
    *ask_user*|*askuser*) return 0 ;;
    *) return 1 ;;
  esac
}

# Parse tool name from PreToolUse / PostToolUse stdin JSON.
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
