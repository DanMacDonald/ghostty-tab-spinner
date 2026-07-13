# xAI plugin marketplace — submission notes

For maintainers opening a PR against
[xai-org/plugin-marketplace](https://github.com/xai-org/plugin-marketplace).

## Suggested catalog entry

Pin `sha` to a full **40-char lowercase commit** (not a tag name). For **v1.0.1**:

```text
a316d6abc3dcae31d44dd9fcd617ddab0c3e9fc4
```

Refresh anytime with:

```bash
git ls-remote https://github.com/DanMacDonald/ghostty-tab-spinner.git HEAD
# or (annotated tag → commit):
git rev-parse v1.0.1^{commit}
```

```json
{
  "name": "ghostty-tab-spinner",
  "description": "Codex-style braille spinner on the terminal tab title while Grok works, plus [!] Action Required when waiting for user input. Pure OSC titles; no network access.",
  "category": "development",
  "source": {
    "source": "url",
    "url": "https://github.com/DanMacDonald/ghostty-tab-spinner.git",
    "sha": "a316d6abc3dcae31d44dd9fcd617ddab0c3e9fc4"
  },
  "homepage": "https://github.com/DanMacDonald/ghostty-tab-spinner",
  "keywords": [
    "ghostty-tab-spinner",
    "ghostty tab spinner",
    "grok tab spinner"
  ]
}
```

Then in the marketplace fork:

```bash
python3 scripts/generate-plugin-index.py
python3 scripts/validate-catalog.py
python3 scripts/generate-plugin-index.py --check
```

## Reviewer FAQ

**What does this plugin ship?**  
Hooks only (`hooks/hooks.json` → `bin/*.sh` + optional `bin/gts-title`). No skills, MCP, or agents.

**Network / secrets?**  
None. See [SECURITY.md](../SECURITY.md).

**Why unrestricted PreToolUse?**  
Keeps the spinner alive for every tool during a turn; hook never denies tools.

**Personal GitHub account**  
Independent open-source tool; not impersonating an xAI or corporate brand. Author: Dan MacDonald.

**Install after marketplace merge**  
`grok plugin install` / `/marketplace` is the discovery path. If hooks do not fire on a given Grok Build version, `./scripts/install.sh` registers the same scripts as global hooks (documented in README).

## PR description template

```markdown
## Add ghostty-tab-spinner

Codex-style terminal **tab title spinner** for Grok Build + Action Required
when the agent needs user input.

- **Source:** https://github.com/DanMacDonald/ghostty-tab-spinner
- **License:** MIT
- **Components:** hooks only (no MCP, no network)
- **Security:** passive OSC title writes to the session PTY; hooks always allow tools
- **Docs:** SECURITY.md, README install paths

### Pin
- sha: `<40-char sha>`

### Checklist
- [x] marketplace.json entry
- [x] plugin-index regenerated
- [x] validate-catalog.py passes
```
