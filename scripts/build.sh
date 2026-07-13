#!/usr/bin/env bash
# Build gts-title and install into bin/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/rust"
cargo build --release
cp -f target/release/gts-title "$ROOT/bin/gts-title"
chmod +x "$ROOT/bin/gts-title"
echo "installed $ROOT/bin/gts-title"
file "$ROOT/bin/gts-title"
