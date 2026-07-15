---
name: web-use-agent
description: Use when asked to run, test, screenshot, or dogfood this repo's own Web-Use browsing agent against a live site (e.g. "browse to X and do Y", "test the agent", "try a query", verifying an agent/browser/tools code change by watching it act, smoke-testing the browser stack). Not for browsing unrelated to this project.
---

# Web-Use Agent

This repo (Web-Use) is itself an autonomous CDP-based browsing agent (Gemini-backed by default). Two verified ways to drive it, both run from the **repo root** (the `src.*` imports require it):

1. **Full agent run** — `src/cli.py`, needs `GOOGLE_API_KEY` in `.env`, burns Gemini calls.
2. **No-LLM smoke driver** — `.claude/skills/web-use-agent/smoke.py`, exercises the real browser stack (launch → navigate → DOM read → screenshot) with no agent and no API key. Use this first for changes to `src/agent/browser/*` or `src/agent/tools/*`.

Use gstack `/browse` instead for any browsing not about exercising this repo's agent.

## Run (no-LLM smoke driver) — start here for browser/tools changes

```bash
uv run python .claude/skills/web-use-agent/smoke.py https://example.com /tmp/smoke.png
```

Prints `title=…`, `h1=…`, the screenshot path, and `SMOKE PASS`/`SMOKE FAIL` (exit code 0/1). ~5s. Launches real headless Chrome via CDP with a fresh temp profile — safe while your own Chrome is open. Look at the screenshot to confirm rendering.

The driver shows the public `Browser` API for ad-hoc probes: `navigate(url)`, `execute_script(js)`, `get_screenshot()`, `get_page_content()`, `scroll_page(dir)` — all on `Browser` used as `async with Browser(BrowserConfig(headless=True)) as b:`.

## Run (full agent)

```bash
uv run python src/cli.py --query "<task description>" [--headless] [--steps N]
uv run python src/cli.py --file <path/to/masterprompt.txt> [--headless] [--steps N]
```

- `--query` | `--file`: exactly one required. `--file` reads the whole file as the task — use it for long/multi-line masterprompts instead of `--query "$(cat file)"`, which leaks the full prompt into the process argument list. Missing file prints `[!] Error: File '…' not found.` and exits 0 (no API call).
- `--headless`: no visible window (default: visible)
- `--steps`: max agent steps (default 100)

Requires `GOOGLE_API_KEY` in `.env` — Gemini (`gemini-2.5-flash`) is hardcoded in `src/cli.py`. Output: `[*] Starting Web-Use Agent...`, streamed `[Agent] 🛠️ Tool Call:` / `📃 Tool Result:` lines, then `[+] Final Agent Response:`. A trivial verified example:

```bash
uv run python src/cli.py --query "Go to https://example.com and tell me the exact text of the page's main heading" --headless --steps 8
```

## Test

```bash
uv run pytest tests/ -q
```

25 tests, ~2s, all mocked (no real browser, no network). Passing tests do NOT prove the browser stack works — run the smoke driver for that.

## Gotchas

- **`main.py` is a hardcoded demo** with `input()` and no argparse — use `src/cli.py` for parameterized runs.
- **Must run from repo root.** Everything imports `src.*`; `cd`ing into `src/` breaks imports.
- **Bare `python3` fails on imports** — always `uv run` (the venv has `google-genai` etc.).
- **Safe alongside your real Chrome.** `use_system_profile=True` copies cookies/session files into a fresh temp dir (`web-use-profile-*`) per launch; it never locks your live profile. The smoke driver uses a clean temp profile with no cookies at all.
- **Port 9222 gets killed.** Default `cdp_port` is 9222; if something unresponsive-or-wrong is listening there, `Browser` will `kill -9` it and launch its own Chrome (`service.py:_kill_on_port`). Don't park anything you care about on 9222.
- **`attach_to_existing=True`** connects to an already-running browser instead of launching — that browser must have been started with `--remote-debugging-port=9222`, else `RuntimeError: nothing is listening on port`.
- **Vision screenshots add ~600ms/step** in the full agent (`use_vision=True` in cli.py); the DOM-state capture itself is <10ms.

## Troubleshooting

- Stack trace right at startup on the full agent → `.env` missing `GOOGLE_API_KEY`.
- `ModuleNotFoundError: No module named 'src'` → you're not at the repo root, or you dropped `uv run`.
