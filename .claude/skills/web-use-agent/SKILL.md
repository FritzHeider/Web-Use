---
name: web-use-agent
description: Use when asked to run, test, or dogfood this repo's own Web-Use browsing agent against a live site (e.g. "browse to X and do Y", "test the agent", "try a query", verifying an agent code change by watching it act, exploring a use case for this tool). Not for browsing unrelated to this project.
---

# Web-Use Agent

## Overview
This repo (Web-Use) is itself an autonomous CDP-based browsing agent (Gemini-backed by default). When the task is to exercise *this project's* agent — not generic web browsing — invoke it directly via `src/cli.py` instead of gstack `/browse` or `claude-in-chrome`.

## When to Use
- Testing/debugging a change to the agent code in this repo
- Verifying `src/cli.py`, a provider, or a tool end-to-end against a real site
- Running one of this project's own use cases as a real invocation (not a mockup)

Use gstack `/browse` instead for anything not about exercising this repo's agent.

## Running a Task
```bash
uv run python src/cli.py --query "<task description>" [--headless] [--steps N]
```
- `--query` (required): natural-language task for the agent
- `--headless`: run without a visible window (default: visible, uses the system Chrome profile)
- `--steps`: max agent steps (default 100)

Requires `GOOGLE_API_KEY` in `.env` — Gemini is the default provider (see `src/cli.py`).

## Reading Output
The CLI prints `[*] Starting Web-Use Agent...`, streams the agent's actions as it navigates, then prints `[+] Final Agent Response:` with the result. A stack trace usually means `.env` is missing `GOOGLE_API_KEY` or Chrome isn't installed/discoverable.

## Common Mistakes
- Running `python main.py` expecting CLI args — `main.py` is a hardcoded demo entrypoint with no argparse; use `src/cli.py` for parameterized runs.
- Omitting `uv run` — the project venv has the provider SDKs (`google-genai`, etc.); a bare `python3` outside the venv will fail on imports.
