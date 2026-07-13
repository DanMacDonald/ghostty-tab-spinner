# Security

This document is for users and for xAI plugin-marketplace review.

## Summary

| Property | Value |
|----------|--------|
| Network access | **None** — no HTTP, sockets, telemetry, or downloads |
| Credentials | **None** — does not read tokens, env secrets, SSH keys, or `.env` |
| Filesystem write | Session-local state only (`$TMPDIR/ghostty-tab-spinner/…` or `GROK_PLUGIN_DATA`) plus OSC writes to the **session PTY** |
| Tool blocking | **Never** — hooks always exit 0; no `deny` decisions |
| External binaries | Optional local `bin/gts-title` built from this repo’s Rust source (or bash fallback) |

## What the hooks do

All hooks are **passive**. They:

1. Discover the session TTY (`/dev/ttys*` / `/dev/pts/*`)
2. Write **OSC 0 / OSC 2** title sequences to that PTY
3. Optionally spawn a short-lived local process (`gts-title spin` or a bash loop) that continues writing titles until the turn ends

They do **not** read source code, execute user project commands, or call the network.

### Hook inventory

| Event | Script | Privilege / side effects |
|-------|--------|---------------------------|
| `SessionStart` | `bin/session-start.sh` | Set idle tab title; short background re-assert |
| `UserPromptSubmit` | `bin/on-busy.sh` | Start braille spinner process |
| `PreToolUse` | `bin/on-activity.sh` | Keep spinner alive; never blocks tools |
| `PostToolUse` / `PostToolUseFailure` | `bin/on-post-tool.sh` | Clear Action Required; resume spinner |
| `Notification` | `bin/on-notification.sh` | Action Required title for permission / elicitation |
| `Stop` / `StopFailure` | `bin/on-idle.sh` | Stop spinner; restore project title |
| `SessionEnd` | `bin/session-end.sh` | Cleanup |

### Why `PreToolUse` has no tool matcher

The braille spinner must stay healthy across **all** tools for the duration of a turn. A matcher limited to `Bash`/`Write` would drop the spinner during reads, greps, and MCP tools. The hook:

- Does **not** inspect tool arguments beyond the tool name (for `ask_user_question` only)
- Always **allows** the tool (`exit 0`, no deny JSON)
- Is intentionally fail-open (`set +e`, ignored errors)

## Install surfaces

1. **Global hooks** (`./scripts/install.sh`) — writes `~/.grok/hooks/ghostty-tab-spinner.json` with absolute paths into this clone
2. **Plugin install** (`grok plugin install … --trust`) — uses `hooks/hooks.json` with `${GROK_PLUGIN_ROOT}`

Both invoke the same scripts under `bin/`.

## Supply chain

- Source: https://github.com/DanMacDonald/ghostty-tab-spinner
- License: MIT (`LICENSE`)
- No `postinstall`, no binary downloads, no third-party runtime deps beyond system `bash` / optional `python3` / optional Rust toolchain for building `gts-title`
- `bin/gts-title` is gitignored; users build from `rust/` via `scripts/build.sh`

## Reporting issues

https://github.com/DanMacDonald/ghostty-tab-spinner/issues
