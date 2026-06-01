# claude-statusline-pro

A compact, information-dense [statusline](https://docs.claude.com/en/docs/claude-code/statusline) for Claude Code.

```
⬢ Sonnet 4.6 · ↑15k ↓5k 🧠120k 💰$0.04 · ⣿⣿⣿⣀⣀⣀⣀⣀⣀⣀ 42k/200k · ⏱ 2h14m ⣿⣿⣿⣿⣀⣀ 62% · 📆 6d14h ⣿⣀⣀⣀ 7% · 💳 $0.12/$5
```

## Install

```bash
npx @pranav2012/claude-statusline-pro
```

That single command:

1. Copies `statusline-command.sh` into `~/.claude/` (respects `CLAUDE_CONFIG_DIR`).
2. Backs up your existing `~/.claude/settings.json` to `settings.json.bak`.
3. Wires up the `statusLine` block in `settings.json`.

Start a new Claude Code session (or run `/statusline`) and it appears.

## What it shows

| Segment | Meaning |
| --- | --- |
| `⬢ Sonnet 4.6` | Active model |
| `↑ ↓ 🧠 💰` | Input / output / cache-read tokens and session cost |
| `⣿⣿⣀ 42k/200k` | Context-window usage bar (green → yellow → red) |
| `⏱ 2h14m … 62%` | 5-hour session usage + time to reset |
| `📆 6d14h … 7%` | 7-day rolling usage + time to reset |
| `💳 $0.12/$5` | Extra-usage spend vs. monthly budget (only if enabled) |

The usage / budget segments come from the Claude OAuth usage API. Credentials are read
from the macOS Keychain, falling back to `~/.claude/.credentials.json` on Linux/Windows.
Results are cached for 60s in `/tmp`.

## Requirements

`bash`, `jq`, `python3`, and `curl` on `PATH`. The installer warns about any that are missing.
The model / token / cost / context segments work without network access; the usage and
budget segments require valid Claude Code credentials.

## License

MIT
