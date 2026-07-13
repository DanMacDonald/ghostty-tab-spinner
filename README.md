# ghostty-tab-spinner

Codex-style **braille spinner** on the terminal tab/window title while
[Grok](https://grok.x.ai) is working — plus an **Action Required** pulse when
the agent is waiting for you (permissions, `ask_user_question`, etc.).

Cross-platform pure **OSC 0** to the session PTY. No AppleScript / GUI automation.

## Titles

| Situation | Title |
|-----------|--------|
| One live Grok session for this project | `MyProject` |
| Another live session shares the same project basename | `MyProject - Grok` |
| Agent busy | `⠋ MyProject` (animating braille) |
| Waiting for your input | `[!] Action Required` ↔ `[.] Action Required` |

## Requirements

- [Grok CLI](https://github.com/xai-org) with plugins/hooks
- A terminal that honors OSC 0 titles (Ghostty, kitty, iTerm2, most xterms, …)
- Optional: [Rust](https://rustup.rs) toolchain to build `gts-title` (faster path; bash fallback exists)

## Install (development / local)

```bash
# Clone or place this repo somewhere stable, then link into Grok's plugin dir:
git clone <your-fork-url> ~/Projects/Grok/ghostty-tab-spinner
mkdir -p ~/.grok/plugins
ln -sfn ~/Projects/Grok/ghostty-tab-spinner ~/.grok/plugins/ghostty-tab-spinner

# Build the Rust helper (recommended)
./scripts/build.sh
```

Enable in `~/.grok/config.toml`:

```toml
[ui.notifications.title]
enabled = false   # critical — Grok must not fight OSC titles

[plugins]
enabled = ["ghostty-tab-spinner"]
```

**Do not** also install a second copy under `~/.grok/hooks/` — it races the
plugin and can break tools if scripts fail.

Restart Grok (or start a new session) after installing.

## How it works

```text
UserPromptSubmit  →  start braille spinner (OSC 0 @ ~100ms)
PreToolUse        →  keep spinner; ask_user_question → Action Required alert
Notification      →  elicitation_dialog / permission_prompt → Action Required
PostToolUse       →  clear alert, resume braille
Stop              →  restore project title (no artificial delay)
```

Hooks inject OSC into the session PTY (`/dev/ttys*` / `/dev/pts/*`) via a small
Rust binary (`bin/gts-title`), matching Codex’s `terminal_title.rs` framing:

```text
ESC ] 0 ; {frame} {label} BEL
```

## Rebuild

```bash
./scripts/build.sh
# or:
(cd rust && cargo build --release && cp -f target/release/gts-title ../bin/gts-title)
```

## Configuration (environment)

| Variable | Default | Meaning |
|----------|---------|---------|
| `GHOSTTY_TAB_SPINNER_INTERVAL` | `0.1` | Seconds between braille frames |
| `GHOSTTY_TAB_SPINNER_ASCII=1` | off | ASCII `\| / - \` frames |
| `GHOSTTY_TAB_SPINNER_DEBUG=1` | off | Verbose hook logs |
| `GHOSTTY_TAB_SPINNER_FORCE_DISAMBIG=1` | off | Always append ` - Grok` |
| `GHOSTTY_TAB_SPINNER_ALERT_TITLE` | `Action Required` | Alert label |
| `GHOSTTY_TAB_SPINNER_ALERT_INTERVAL` | `0.5` | Seconds between `[!]` / `[.]` |

Per-session logs (debug):  
`~/.grok/plugin-data/**/ghostty-tab-spinner/sessions/<id>/hook.log`

## Layout

```text
bin/           # hook scripts + gts-title binary
hooks/         # Grok hooks.json
rust/          # gts-title (OSC 0 helper)
plugin.json    # plugin manifest
scripts/build.sh
```

## Notes

- Tab spinner stops on the `Stop` hook; the TUI “Responding…” indicator is
  internal to Grok and is not exposed to plugins, so they may not end in
  perfect lockstep.
- Action Required depends on Grok emitting `Notification`
  (`elicitation_dialog`, `permission_prompt`, …) and/or `PreToolUse` for
  `ask_user_question`.

## License

MIT
