#!/usr/bin/env bash
# Remove global hooks + plugin symlink for ghostty-tab-spinner.
set -euo pipefail

PLUGIN_NAME="ghostty-tab-spinner"
GROK_HOME="${GROK_HOME:-$HOME/.grok}"
HOOK_JSON="$GROK_HOME/hooks/${PLUGIN_NAME}.json"
LINK="$GROK_HOME/plugins/$PLUGIN_NAME"

removed=0
if [[ -e "$HOOK_JSON" || -L "$HOOK_JSON" ]]; then
  rm -f "$HOOK_JSON"
  echo "removed $HOOK_JSON"
  removed=1
fi

if [[ -L "$LINK" ]]; then
  rm -f "$LINK"
  echo "removed symlink $LINK"
  removed=1
elif [[ -e "$LINK" ]]; then
  echo "left in place (not a symlink): $LINK" >&2
fi

if [[ "$removed" -eq 0 ]]; then
  echo "nothing to remove"
else
  echo "Restart Grok so hooks unload."
fi
