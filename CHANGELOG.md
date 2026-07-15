# Changelog

## Unreleased

- Always use `{project} - Grok` for idle and busy tab titles
- Clear spinner on Ctrl-C / cancel even when Stop hooks do not fire: watch Grok's
  session `events.jsonl` for `turn_ended` (including `outcome: cancelled`)
- Fix events path discovery when `GROK_WORKSPACE_ROOT` has a trailing slash
  (was the reason spinner never attached to events.jsonl)
- Also treat `idle_prompt` / `agent_completed` notifications as idle
- Soft-stop the spinner process (SIGTERM first) so the idle title is restored

## 1.0.1

- Add `.grok-plugin/plugin.json` (Grok-native manifest)
- Add `SECURITY.md` and marketplace review notes
- Align package metadata (homepage, repository, license, keywords)
- Clarify install paths and hook security model in README

## 1.0.0

- First public release
- Codex-style OSC tab spinner + Action Required
- `scripts/install.sh` / `scripts/uninstall.sh`
- Global-hooks install path (reliable); plugin hooks optional
