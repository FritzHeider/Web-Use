---
name: web-use
description: Use when a task needs autonomous, multi-step web browsing beyond simple fetch/click — dynamic React/Vue pages, multi-page form filling or checkout, cross-site search-and-summarize, OAuth/login flows, file download/upload — and you want to delegate it to the Web-Use CDP browsing agent. Bootstraps its own install; not tied to any repo you're already in.
---

# Web-Use (installable browsing agent)

Web-Use is a standalone autonomous browsing agent (Chrome DevTools Protocol + vision + semantic DOM tree, multi-LLM). This skill **installs it if missing** and drives it via its CLI, so it works dropped into any Claude setup — you do not need to already be inside the Web-Use repo.

Original project: `CursorTouch/Web-Use`. The `src/cli.py` wrapper this skill calls lives in the fork below.

## When to use

- Heavy dynamic content (React/Vue/JS) needing waits and real interaction
- Multi-page forms, checkouts, wizards
- Search across several sites, then aggregate/summarize
- OAuth / login flows, persistent sessions
- Download files or upload to forms

**When NOT to use:** a single static page fetch, one obvious click, or scraping one URL — a plain HTTP fetch or the host's built-in browser tool is faster. Web-Use is for *multi-step* autonomy.

## Install (run once; skip if `Web-Use/` already present)

Requires **Python ≥3.13** and **uv** (`curl -LsSf https://astral.sh/uv/install.sh | sh`).

```bash
git clone https://github.com/FritzHeider/Web-Use.git
cd Web-Use
uv sync
printf 'GEMINI_API_KEY="<YOUR_GEMINI_KEY>"\n' > .env
```

Either `GEMINI_API_KEY` or `GOOGLE_API_KEY` works — `ChatGoogle` checks them in that order.

The CLI defaults to the **`gemini-flash-latest`** alias rather than a pinned id on purpose: model availability is per-key/project, so a pinned id (e.g. `gemini-2.5-flash`) can 404 for a fresh install even while appearing in ListModels.

Other providers (Anthropic, OpenAI, Groq, Ollama, …) ship in deps but the CLI hardcodes Gemini; swap the provider in `src/cli.py` (`ChatGoogle`) to change it.

## Run (from the repo root)

```bash
uv run python src/cli.py --query "<task>" [--headless] [--steps N]
uv run python src/cli.py --file  <path/to/masterprompt.txt> [--headless] [--steps N]
```

- `--query` **or** `--file` (exactly one). Use `--file` for long/multi-line prompts so the full text doesn't leak into the process arg list.
- `--headless`: no visible window (default: visible). `--steps`: max agent steps (default 100).

Streams `[Agent] 🛠️ Tool Call:` / `📃 Tool Result:` lines, then `[+] Final Agent Response:`.

### Verified example

Run end-to-end on 2026-07-29 (agent navigated, read the `h1`, and returned a final answer):

```bash
uv run python src/cli.py --query "Go to https://example.com and tell me the exact text of the main heading" --headless --steps 8
```

## Gotchas

- **Run from the repo root** — everything imports `src.*`; `cd src/` breaks imports.
- **Always `uv run python …`** — bare `python3` misses the venv deps; and don't drop the `python` (`uv run src/cli.py` won't work).
- **Startup stack trace** → `.env` is missing `GEMINI_API_KEY` / `GOOGLE_API_KEY`.
- **`404 ... is no longer available to new users`** → the configured model was retired for your key. Prefer the `gemini-flash-latest` alias over a pinned id. Note a model can be listed by ListModels and still 404 on `generateContent`, so probe with a real call before pinning.
- **`ModuleNotFoundError: No module named 'src'`** → not at repo root, or you dropped `uv run`.
- **Safe alongside your own Chrome** — `use_system_profile` copies session files into a fresh temp profile per launch; it never locks your live browser.
- **Port 9222** is the default CDP port; an unresponsive listener there gets killed and replaced. Don't park anything you care about on it.
- **`main.py` is an interactive demo** (`input()`, no args) — use `src/cli.py` for parameterized/automated runs.

## Distributing this skill

Copy this `web-use/` folder into a target setup's skills directory (e.g. `~/.claude/skills/web-use/`). It is self-contained: the Install section bootstraps the agent on first use.
