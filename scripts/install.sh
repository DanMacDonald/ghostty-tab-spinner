#!/usr/bin/env bash
# Install ghostty-tab-spinner for Grok Build:
#   1) build gts-title (optional if cargo missing)
#   2) symlink into ~/.grok/plugins/
#   3) write global hooks with absolute paths (reliable path)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_NAME="ghostty-tab-spinner"
GROK_HOME="${GROK_HOME:-$HOME/.grok}"
PLUGINS_DIR="$GROK_HOME/plugins"
HOOKS_DIR="$GROK_HOME/hooks"
HOOK_JSON="$HOOKS_DIR/${PLUGIN_NAME}.json"
LINK="$PLUGINS_DIR/$PLUGIN_NAME"

SKIP_BUILD=0
NO_PLUGIN_LINK=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    --no-plugin-link) NO_PLUGIN_LINK=1 ;;
    -h|--help)
      cat <<EOF
Usage: ./scripts/install.sh [--skip-build] [--no-plugin-link]

  --skip-build       Do not run cargo build (use existing bin/gts-title or bash fallback)
  --no-plugin-link   Skip symlink into ~/.grok/plugins/

Installs global hooks to:
  $HOOK_JSON

Also ensure in ~/.grok/config.toml:

  [ui.notifications.title]
  enabled = false
EOF
      exit 0
      ;;
    *)
      echo "unknown arg: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

echo "==> root: $ROOT"

# --- build -----------------------------------------------------------------
if [[ "$SKIP_BUILD" -eq 0 ]]; then
  if command -v cargo >/dev/null 2>&1; then
    echo "==> building gts-title"
    bash "$ROOT/scripts/build.sh"
  else
    echo "==> cargo not found; skipping build (bash spinner fallback will be used)"
    if [[ ! -x "$ROOT/bin/gts-title" ]]; then
      echo "    note: bin/gts-title missing — install Rust later and re-run ./scripts/build.sh"
    fi
  fi
else
  echo "==> skipping build (--skip-build)"
fi

# --- plugin symlink --------------------------------------------------------
if [[ "$NO_PLUGIN_LINK" -eq 0 ]]; then
  mkdir -p "$PLUGINS_DIR"
  ln -sfn "$ROOT" "$LINK"
  echo "==> linked $LINK -> $ROOT"
else
  echo "==> skipped plugin link (--no-plugin-link)"
fi

# --- global hooks ----------------------------------------------------------
mkdir -p "$HOOKS_DIR"
python3 - "$ROOT" "$HOOK_JSON" <<'PY'
import json, pathlib, sys

root = sys.argv[1]
out = pathlib.Path(sys.argv[2])

events = {
    "SessionStart": ("session-start.sh", 5),
    "UserPromptSubmit": ("on-busy.sh", 5),
    "PreToolUse": ("on-activity.sh", 5),
    "PostToolUse": ("on-post-tool.sh", 5),
    "PostToolUseFailure": ("on-post-tool.sh", 5),
    "Notification": ("on-notification.sh", 5),
    "Stop": ("on-idle.sh", 8),
    "StopFailure": ("on-idle.sh", 8),
    "SessionEnd": ("session-end.sh", 8),
}

hooks = {}
for ev, (script, timeout) in events.items():
    path = f"{root}/bin/{script}"
    hooks[ev] = [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": f'bash "{path}"',
                    "timeout": timeout,
                }
            ]
        }
    ]

doc = {
    "description": "ghostty-tab-spinner — Codex-style tab spinner + Action Required",
    "hooks": hooks,
}
out.write_text(json.dumps(doc, indent=2) + "\n")
print(f"==> wrote {out}")
PY

# --- config reminder -------------------------------------------------------
CONFIG="$GROK_HOME/config.toml"
if [[ -f "$CONFIG" ]] && grep -q '\[ui.notifications.title\]' "$CONFIG" 2>/dev/null; then
  if grep -A2 '\[ui.notifications.title\]' "$CONFIG" | grep -q 'enabled\s*=\s*false'; then
    echo "==> [ui.notifications.title] enabled = false already set"
  else
    echo "==> WARNING: set [ui.notifications.title] enabled = false in $CONFIG"
    echo "    (Grok's built-in titles will fight the spinner otherwise)"
  fi
else
  echo "==> add to $CONFIG:"
  echo ""
  echo "    [ui.notifications.title]"
  echo "    enabled = false"
  echo ""
fi

echo ""
echo "Done. Restart Grok (start or resume a session) to load hooks."
echo "  hooks:  $HOOK_JSON"
echo "  plugin: $LINK"
echo "  logs:   \$TMPDIR/ghostty-tab-spinner/<session>/sessions/<id>/hook.log"
