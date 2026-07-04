---
name: web-use
description: Autonomous browsing agent capable of complex multi-step web navigation, form filling, and data extraction using CDP and Vision.
---

# 🌐 Web-Use Skill

This skill allows an agent to delegate complex web browsing tasks to a specialized autonomous agent. Use this when the built-in browser tools are insufficient for highly dynamic pages, complex auth flows, or multi-step navigation.

## Usage

Invoke the browsing agent by running the CLI wrapper. It will handle the navigation and return a summary of its findings.

### Basic Command
```bash
uv run src/cli.py --query "your request here"
```

### Options
- `--headless`: Run the browser without a GUI (faster, but may fail on some interactive checks).
- `--steps <N>`: Maximum number of steps to allow the agent (default: 100).

## When to use this skill
- **Dynamic Content**: Pages with heavy React/Vue/JS that require waiting or complex interactions.
- **Form Filling**: Multi-page forms or complex checkouts.
- **Search & Aggregate**: Finding information across multiple sites and summarizing it.
- **OAuth/Auth**: Situations requiring complex login flows or persistent sessions.

## Example
```bash
uv run src/cli.py --query "Find the top 3 trending AI papers on arXiv from the last week and summarize their abstracts."
```
