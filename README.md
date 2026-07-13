# ghostty-tab-spinner

Codex-style **braille spinner** on the terminal tab title while
[Grok](https://grok.x.ai) is working — plus **Action Required** when the agent
is waiting for you (permissions, `ask_user_question`, etc.).

Pure **OSC 0/2** written to the session PTY. No AppleScript / GUI automation.

## Titles

| Situation | Title |
|-----------|--------|
| One live Grok session for this project | `MyProject` |
| Another live session shares the same basename | `MyProject - Grok` |
| Agent busy | `⠋ MyProject` (animating braille) |
| Waiting for your input | `[!] Action Required` ↔ `[.] Action Required` |

## Requirements

- [Grok CLI](https://github.com/xai-org) with hooks
- Terminal that honors OSC titles (Ghostty, kitty, iTerm2, most xterms, …)
- Optional: [Rust](https://rustup.rs) to build `gts-title` (bash fallback exists)

## Install

### Why global hooks / local path (recommended)

This plugin is almost entirely **hooks**. Grok can discover a plugin under
`~/.grok/plugins/` (and list it as enabled with hooks present), but **plugin
hook expansion is flaky** on some Grok Build versions (0.2.x): the plugin
shows up in `/plugins` / `grok inspect`, yet `SessionStart` / `UserPromptSubmit`
never run.

So many installs do **not** rely on the plugin system to execute hooks. Instead:

1. Keep the repo at a **stable local path** (or symlink into `~/.grok/plugins/`).
2. Register the same scripts as **global hooks** under `~/.grok/hooks/` with
   **absolute paths** — those always load and fire.

Optional `grok plugin install` / marketplace listing is fine for discovery;
treat **global hooks** as the path that actually runs the spinner until plugin
hooks are reliable end-to-end.

Do **not** install a second competing copy under both a broken plugin path and
global hooks that point at different trees unless you know only one is firing.

### Steps (recommended)

```bash
git clone https://github.com/DanMacDonald/ghostty-tab-spinner.git
cd ghostty-tab-spinner
./scripts/install.sh
```

`install.sh` will:

1. Build `bin/gts-title` if `cargo` is available (else bash fallback)
2. Symlink the repo into `~/.grok/plugins/ghostty-tab-spinner`
3. Write **global hooks** to `~/.grok/hooks/ghostty-tab-spinner.json` (absolute paths)

In `~/.grok/config.toml`:

```toml
[ui.notifications.title]
enabled = false   # critical — Grok must not fight OSC titles
```

Restart Grok after installing. (Session picker still shows `grok` until you
start/resume a session — there is no earlier hook than `SessionStart`.)

```bash
# Options
./scripts/install.sh --skip-build      # keep existing binary / bash fallback
./scripts/install.sh --no-plugin-link  # hooks only
./scripts/uninstall.sh                 # remove hooks + plugin symlink
```

### Optional: plugin-only install

```bash
grok plugin install https://github.com/DanMacDonald/ghostty-tab-spinner.git --trust
# and/or enable in config:
# [plugins]
# enabled = ["ghostty-tab-spinner"]
```

If the tab stays `grok` and never spins, check `/hooks` and run
`./scripts/install.sh` — that usually means plugin hooks were discovered but
not executed.

## How it works

```text
SessionStart      →  idle project title (+ re-assert vs "grok" race)
UserPromptSubmit  →  start braille spinner (~100ms)
PreToolUse        →  keep spinner; ask_user_question → Action Required
Notification      →  permission / elicitation → Action Required
PostToolUse       →  clear alert, resume braille
Stop              →  restore project title
```

## Rebuild

```bash
./scripts/build.sh
# or re-run the full installer:
./scripts/install.sh
```

## Configuration (environment)

| Variable | Default | Meaning |
|----------|---------|---------|
| `GHOSTTY_TAB_SPINNER_INTERVAL` | `0.1` | Seconds between braille frames |
| `GHOSTTY_TAB_SPINNER_ASCII=1` | off | ASCII `\| / - \` frames |
| `GHOSTTY_TAB_SPINNER_DEBUG=1` | off | Verbose hook logs to stderr |
| `GHOSTTY_TAB_SPINNER_FORCE_DISAMBIG=1` | off | Always append ` - Grok` |
| `GHOSTTY_TAB_SPINNER_ALERT_TITLE` | `Action Required` | Alert label |
| `GHOSTTY_TAB_SPINNER_ALERT_INTERVAL` | `0.5` | Seconds between `[!]` / `[.]` |

Logs: `$TMPDIR/ghostty-tab-spinner/<session>/sessions/<id>/hook.log`  
(or under `~/.grok/plugin-data/` when run as a trusted plugin with data dir)

## Layout

```text
bin/                 # hook scripts + gts-title
hooks/               # plugin hooks.json (optional / discovery)
rust/                # gts-title source
scripts/install.sh   # recommended installer
scripts/uninstall.sh
scripts/build.sh
plugin.json
```

## License

MIT
