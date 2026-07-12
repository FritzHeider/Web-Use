"""No-LLM smoke driver for the Web-Use browser stack.

Launches the real headless Chrome via CDP, navigates, reads the DOM, and
saves a screenshot — without an agent or API key. Use it to verify changes
to src/agent/browser/* or src/agent/tools/* end-to-end for free.

Run from the repo root:
    uv run python .claude/skills/web-use-agent/smoke.py [url] [screenshot.png]
"""
import asyncio
import sys

from src.agent.browser.config import BrowserConfig
from src.agent.browser.service import Browser


async def main():
    url = sys.argv[1] if len(sys.argv) > 1 else 'https://example.com'
    shot_path = sys.argv[2] if len(sys.argv) > 2 else 'smoke-screenshot.png'

    config = BrowserConfig(browser='chrome', headless=True)
    async with Browser(config) as browser:
        await browser.navigate(url)
        title = await browser.execute_script('document.title')
        h1 = await browser.execute_script("document.querySelector('h1')?.textContent ?? '(no h1)'")
        png = await browser.get_screenshot()
        if png:
            with open(shot_path, 'wb') as f:
                f.write(png)

        ok = bool(title) and png is not None
        print(f'url={url}')
        print(f'title={title!r}')
        print(f'h1={h1!r}')
        print(f'screenshot={shot_path} ({len(png) if png else 0} bytes)')
        print('SMOKE PASS' if ok else 'SMOKE FAIL')
        return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(asyncio.run(main()))
