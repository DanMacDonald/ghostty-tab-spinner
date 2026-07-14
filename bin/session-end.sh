#!/usr/bin/env bash
set +e
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
go_idle 2>/dev/null || true
exit 0
