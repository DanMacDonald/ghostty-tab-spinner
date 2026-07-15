# ghostty-tab-spinner

Codex-style **braille spinner** on the terminal tab title while
[Grok](https://grok.x.ai) is working — plus **Action Required** when the agent
is waiting for you (permissions, `ask_user_question`, etc.).

Pure **OSC 0/2** written to the session PTY. No AppleScript, no network, no
credentials. MIT licensed.

| Situation | Title |
|-----------|--------|
| Idle | `MyProject - Grok` |
| Agent busy | `⠋ MyProject - Grok` (animating braille) |
| Waiting for your input | `[!] Action Required` ↔ `[.] Action Required` |

**Note:** This changes Grok’s default tab-title behavior. Instead of the built-in
verbose status messages on the tab, you get `{project} - Grok` (with a spinner
while the agent is working, and **Action Required** when input is needed). That
is intentional: the install steps disable Grok’s own title updates so they do
not fight this plugin.

## Requirements

- [Grok Build](https://grok.x.ai) (hooks support)
- Terminal that honors OSC titles (Ghostty, kitty, iTerm2, most xterms, …)
- `bash`, `python3` (for a few helpers)
- Optional: [Rust](https://rustup.rs) to build `gts-title` (bash fallback exists)

## Install

### Recommended: installer (global hooks)

```bash
git clone https://github.com/DanMacDonald/ghostty-tab-spinner.git
cd ghostty-tab-spinner
./scripts/install.sh
```

This will:

1. Build `bin/gts-title` if `cargo` is available
2. Symlink into `~/.grok/plugins/ghostty-tab-spinner`
3. Write **global hooks** to `~/.grok/hooks/ghostty-tab-spinner.json` (absolute paths into this clone)

**Required config** in `~/.grok/config.toml`:

```toml
[ui.notifications.title]
enabled = false   # so Grok does not fight OSC titles
```

Restart Grok (start or resume a **session** — the session picker has no hooks yet).

```bash
./scripts/install.sh --skip-build      # keep existing binary / bash fallback
./scripts/install.sh --no-plugin-link  # hooks only
./scripts/uninstall.sh                 # remove hooks + plugin symlink
```

### Plugin install (marketplace / CLI)

```bash
grok plugin install https://github.com/DanMacDonald/ghostty-tab-spinner.git --trust
```

Or install from the xAI marketplace once listed (`/marketplace`).

If titles never change after a plugin-only install, use `./scripts/install.sh`
(global hooks). See [Install paths](#install-paths).

## How it works

```text
SessionStart      →  idle "{project} - Grok" (+ short re-assert vs default "grok")
UserPromptSubmit  →  start braille spinner on "{project} - Grok" (~100ms)
PreToolUse        →  keep spinner; ask_user_question → Action Required
Notification      →  permission / elicitation → Action Required;
                      idle_prompt / agent_completed → clear spinner
PostToolUse       →  clear alert, resume braille
Stop / SessionEnd →  restore "{project} - Grok"
(spinner also tails ~/.grok/sessions/…/events.jsonl for turn_ended —
 covers Ctrl-C cancel when Stop hooks skip)
```

Hooks are **passive** (always allow tools). Details: [SECURITY.md](SECURITY.md).

## Install paths

| Path | Role |
|------|------|
| `./scripts/install.sh` → `~/.grok/hooks/` | **Reliable execution** — global hooks with absolute script paths |
| `~/.grok/plugins/` symlink or `grok plugin install` | Discovery / marketplace / `GROK_PLUGIN_ROOT` |
| Plugin `hooks/hooks.json` only | Works when Grok expands plugin hooks; if not, use the installer |

Do not point global hooks and a second copy of the scripts at different trees
unless you intend only one to run.

## Configuration (environment)

| Variable | Default | Meaning |
|----------|---------|---------|
| `GHOSTTY_TAB_SPINNER_INTERVAL` | `0.1` | Seconds between braille frames |
| `GHOSTTY_TAB_SPINNER_ASCII=1` | off | ASCII `\| / - \` frames |
| `GHOSTTY_TAB_SPINNER_DEBUG=1` | off | Verbose logs to stderr |
| `GHOSTTY_TAB_SPINNER_ALERT_TITLE` | `Action Required` | Alert label |
| `GHOSTTY_TAB_SPINNER_ALERT_INTERVAL` | `0.5` | Seconds between `[!]` / `[.]` |

Logs: `$TMPDIR/ghostty-tab-spinner/<session>/sessions/<id>/hook.log`  
(or under `~/.grok/plugin-data/` when the plugin data dir is set)

## Rebuild

```bash
./scripts/build.sh
# or
./scripts/install.sh
```

## Layout

```text
.grok-plugin/plugin.json   # Grok-native manifest
.claude-plugin/plugin.json # Claude-compatible alias
bin/                       # hook scripts + gts-title (built)
hooks/hooks.json           # plugin hooks
rust/                      # gts-title source
scripts/install.sh
scripts/uninstall.sh
scripts/build.sh
SECURITY.md
docs/MARKETPLACE.md        # catalog PR notes for xAI marketplace
```

## Security

No network, no secrets, never blocks tools. See [SECURITY.md](SECURITY.md).

## Marketplace

Notes for listing on [xai-org/plugin-marketplace](https://github.com/xai-org/plugin-marketplace):
[docs/MARKETPLACE.md](docs/MARKETPLACE.md).

## License

[MIT](LICENSE) © Dan MacDonald
