#!/usr/bin/env bash
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
cancel_idle_grace
stop_alert_loop 0
stop_spinner_loop
set_title_osc "$(idle_title)" || true
exit 0
