#!/usr/bin/env bash
# Manual: re-apply Codex idle title for this session.
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
should_run || exit 0
capture_tty >/dev/null 2>&1
set_title_osc "$(idle_title)" || true
echo "$(idle_title)"
