# Dropdown-Select Tool Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **For ralph-orchestrator:** Each loop iteration: (1) read this file, (2) find the first unchecked `- [ ]` step, (3) execute that step exactly as written, (4) mark it `- [x]` and save this file, (5) if the step is a Commit step, include this plan file in the commit. **Stop condition:** every checkbox is `- [x]` AND `uv run pytest tests/ -v` passes — when (and only when) both hold, output the completion promise `LOOP_COMPLETE`. Never skip ahead; never re-do checked steps. If a test that should fail passes (or vice versa), stop and record the discrepancy under a `## Blockers` heading at the bottom of this file instead of improvising.

**Goal:** Register the existing `menu_tool` with the agent and make dropdown selection report real success/failure so the agent can self-correct.

**Architecture:** `menu_tool` is added to `BUILTIN_TOOLS`. The injected JS in `Browser.select_option` returns a structured result (`selected` / `notFound` / `available`, or an `error` marker) instead of a bare boolean; `menu_tool` inspects that result and raises on any failure so the agent loop sees a failed action with actionable text. `Page.select_option_at` gets the same JS body for parity. Option labels are always embedded via `json.dumps`, which keeps quoting safe for labels like `Mechanic's Lien`.

**Tech Stack:** Python 3 (asyncio), CDP via existing `Browser`/`Page` services, pytest (mock-based unit tests, no live browser).

**Spec:** `docs/superpowers/specs/2026-07-04-dropdown-select-tool-design.md`

## Global Constraints

- Native `<select>` elements only — no custom-dropdown handling.
- No new dependencies. Async code in tests runs via `asyncio.run(...)` (there is no pytest-asyncio in this project).
- Exact-match label comparison against `option.text.trim()` — no fuzzy matching.
- `available` option list truncated to the first 30 entries.
- Run tests with `uv run pytest ...` from the repo root (`/Users/drop/Web-Use`).
- All tests live in `tests/`; never create files at the repo root.
- Commit messages: conventional style (`feat:`, `test:`), no `Co-Authored-By` trailer.
- ALWAYS read a file before editing it.

---

### Task 1: Register `menu_tool` in `BUILTIN_TOOLS`

**Files:**
- Modify: `src/agent/tools/__init__.py:20-25`
- Test: `tests/test_menu_tool.py` (create)

**Interfaces:**
- Consumes: `menu_tool` (existing `Tool` instance defined in `src/agent/tools/service.py`).
- Produces: `menu_tool` present in `src.agent.tools.BUILTIN_TOOLS` — the agent (`src/agent/service.py:52`) picks it up automatically. The test file `tests/test_menu_tool.py` created here is extended by Tasks 2–4.

- [x] **Step 1: Write the failing test**

Create `tests/test_menu_tool.py` with exactly:

```python
import asyncio
import json
from unittest.mock import AsyncMock, MagicMock

import pytest

from src.agent.tools import BUILTIN_TOOLS
from src.agent.tools.service import menu_tool


def test_menu_tool_registered():
    assert menu_tool in BUILTIN_TOOLS
```

- [x] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_menu_tool.py::test_menu_tool_registered -v`
Expected: FAIL with `AssertionError` (menu_tool is imported in `__init__.py` but absent from the `BUILTIN_TOOLS` list).

- [x] **Step 3: Add `menu_tool` to the registration list**

In `src/agent/tools/__init__.py`, change the `BUILTIN_TOOLS` list (currently lines 20–25) from:

```python
BUILTIN_TOOLS = [
    click_tool, goto_tool, key_tool, scrape_tool,
    type_tool, scroll_tool, wait_tool, back_tool,
    tab_tool, done_tool, forward_tool, download_tool,
    script_tool,
]
```

to:

```python
BUILTIN_TOOLS = [
    click_tool, goto_tool, key_tool, scrape_tool,
    type_tool, scroll_tool, wait_tool, back_tool,
    tab_tool, done_tool, forward_tool, download_tool,
    script_tool, menu_tool,
]
```

Do not change the import block or `upload_tool`/`human_tool` handling.

- [x] **Step 4: Run test to verify it passes**

Run: `uv run pytest tests/test_menu_tool.py::test_menu_tool_registered -v`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add tests/test_menu_tool.py src/agent/tools/__init__.py docs/superpowers/plans/2026-07-04-dropdown-select-tool.md
git commit -m "feat: register menu_tool so the agent can select dropdown options"
```

---

### Task 2: `Browser.select_option` returns a structured result

**Files:**
- Modify: `src/agent/browser/service.py:937-951` (the `select_option` method)
- Test: `tests/test_menu_tool.py` (append)

**Interfaces:**
- Consumes: `Browser.execute_script(script: str, truncate: bool = False, repair: bool = False) -> Any` (existing, returns JS values by value — objects arrive as Python dicts).
- Produces: `async def select_option(self, xpath: str, labels: list[str]) -> dict` returning one of:
  - `{'error': 'not_found'}`
  - `{'error': 'not_select', 'tag': '<lowercase tagname>'}`
  - `{'selected': list[str], 'notFound': list[str], 'available': list[str]}`
  Task 3's `menu_tool` consumes exactly these shapes.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_menu_tool.py`:

```python
def _stub_browser(script_result):
    from src.agent.browser.service import Browser
    browser = Browser.__new__(Browser)
    browser.execute_script = AsyncMock(return_value=script_result)
    return browser


def test_select_option_embeds_labels_via_json_dumps():
    browser = _stub_browser({'selected': [], 'notFound': ["Mechanic's Lien"], 'available': ['Deed of Trust']})
    asyncio.run(browser.select_option("//select[1]", ["Mechanic's Lien"]))
    script = browser.execute_script.call_args.args[0]
    assert json.dumps(["Mechanic's Lien"]) in script


def test_select_option_returns_structured_result():
    expected = {'selected': ['BMW'], 'notFound': [], 'available': ['BMW', 'Audi']}
    browser = _stub_browser(expected)
    result = asyncio.run(browser.select_option("//select[1]", ['BMW']))
    assert result == expected


def test_select_option_script_handles_error_shapes():
    browser = _stub_browser({'error': 'not_found'})
    asyncio.run(browser.select_option("//select[1]", ['BMW']))
    script = browser.execute_script.call_args.args[0]
    assert 'not_found' in script
    assert 'not_select' in script
    assert 'available' in script
```

Note: `Browser.__new__(Browser)` skips `__init__` on purpose — `select_option` touches nothing on `self` except `execute_script`, which the stub replaces.

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_menu_tool.py -v`
Expected: `test_menu_tool_registered` and `test_select_option_embeds_labels_via_json_dumps` PASS (the current implementation already uses `json.dumps` — that test pins the existing safe behavior). `test_select_option_returns_structured_result` FAILS (current method returns `None`) and `test_select_option_script_handles_error_shapes` FAILS (current script has no error markers).

- [ ] **Step 3: Rewrite `select_option`**

In `src/agent/browser/service.py`, replace the entire `select_option` method (currently lines 937–951) with:

```python
    async def select_option(self, xpath: str, labels: list[str]) -> dict:
        escaped = xpath.replace('"', '\\"')
        labels_json = json.dumps(labels)
        return await self.execute_script(
            f'(function(){{'
            f'  var el = document.evaluate("{escaped}", document, null, 8, null).singleNodeValue;'
            f'  if (!el) return {{error: "not_found"}};'
            f'  if (el.tagName !== "SELECT") return {{error: "not_select", tag: el.tagName.toLowerCase()}};'
            f'  var labels = {labels_json};'
            f'  var texts = Array.from(el.options).map(function(o){{ return o.text.trim(); }});'
            f'  var selected = labels.filter(function(l){{ return texts.indexOf(l) >= 0; }});'
            f'  var notFound = labels.filter(function(l){{ return texts.indexOf(l) < 0; }});'
            f'  if (selected.length) {{'
            f'    if (el.multiple) {{'
            f'      for (var i = 0; i < el.options.length; i++) el.options[i].selected = labels.indexOf(texts[i]) >= 0;'
            f'    }} else {{'
            f'      el.selectedIndex = texts.indexOf(selected[0]);'
            f'    }}'
            f'    el.dispatchEvent(new Event("input", {{bubbles: true}}));'
            f'    el.dispatchEvent(new Event("change", {{bubbles: true}}));'
            f'  }}'
            f'  return {{selected: selected, notFound: notFound, available: texts.slice(0, 30)}};'
            f'}})()'
        )
```

Semantics locked by the spec: single-select uses the first *requested label* that matched (`selected[0]`); multi-select selects every matching option and deselects options not in `labels`; `input` and `change` both bubble; events fire only when something matched.

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/test_menu_tool.py -v`
Expected: all 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add tests/test_menu_tool.py src/agent/browser/service.py docs/superpowers/plans/2026-07-04-dropdown-select-tool.md
git commit -m "feat: return structured result from select_option instead of silent boolean"
```

---

### Task 3: `menu_tool` interprets the result and raises on failure

**Files:**
- Modify: `src/agent/tools/service.py:255-261` (the `menu_tool` function)
- Test: `tests/test_menu_tool.py` (append)

**Interfaces:**
- Consumes: `Browser.select_option(xpath, labels) -> dict` with the three result shapes from Task 2; `Browser.get_element_by_index(index)` returning an element whose `.xpath` is a dict with key `'element'`.
- Produces: `menu_tool` returns `"Selected <labels> in element at label <N>"` on full success and raises `Exception` with actionable text otherwise. Raising is load-bearing: `Registry.aexecute` (`src/agent/registry/service.py:153-164`) converts it to `ToolResult(is_success=False, error=...)`, which is what the agent loop sees.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_menu_tool.py`:

```python
def _stub_session(select_result):
    element = MagicMock()
    element.xpath = {'element': '//select[1]'}
    session = MagicMock()
    session.get_element_by_index = AsyncMock(return_value=element)
    session.select_option = AsyncMock(return_value=select_result)
    return session


def test_menu_tool_success_message():
    session = _stub_session({'selected': ["Mechanic's Lien"], 'notFound': [], 'available': ["Mechanic's Lien", 'Deed of Trust']})
    message = asyncio.run(menu_tool.ainvoke(index=3, labels=["Mechanic's Lien"], session=session))
    assert "Mechanic's Lien" in message
    assert 'label 3' in message


def test_menu_tool_raises_with_available_options_on_mismatch():
    session = _stub_session({'selected': [], 'notFound': ["Mechanic's Lien"], 'available': ['Mechanic’s Lien', 'Deed of Trust']})
    with pytest.raises(Exception) as exc_info:
        asyncio.run(menu_tool.ainvoke(index=3, labels=["Mechanic's Lien"], session=session))
    assert 'Mechanic’s Lien' in str(exc_info.value)
    assert 'Available options' in str(exc_info.value)


def test_menu_tool_raises_on_non_select_element():
    session = _stub_session({'error': 'not_select', 'tag': 'div'})
    with pytest.raises(Exception) as exc_info:
        asyncio.run(menu_tool.ainvoke(index=5, labels=['BMW'], session=session))
    assert 'not a <select>' in str(exc_info.value)
    assert 'click_tool' in str(exc_info.value)


def test_menu_tool_raises_on_element_not_found():
    session = _stub_session({'error': 'not_found'})
    with pytest.raises(Exception) as exc_info:
        asyncio.run(menu_tool.ainvoke(index=7, labels=['BMW'], session=session))
    assert 'label 7' in str(exc_info.value)
```

(The mismatch test deliberately uses a curly apostrophe `’` in `available` vs a straight `'` in the request — the exact self-correction scenario from the spec.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `uv run pytest tests/test_menu_tool.py -v`
Expected: previous 4 tests PASS; `test_menu_tool_success_message` PASSES incidentally (current code always claims success) but the three `raises` tests FAIL with `DID NOT RAISE`.

- [ ] **Step 3: Rewrite `menu_tool`**

In `src/agent/tools/service.py`, replace the `menu_tool` function (currently lines 255–261) with:

```python
@Tool('menu_tool', model=Menu)
async def menu_tool(index: int, labels: list[str], session: Browser = None):
    '''Selects one or more options in a <select> dropdown by their visible label text.'''
    element = await session.get_element_by_index(index=index)
    xpath   = element.xpath.get('element', '')
    result  = await session.select_option(xpath, labels)
    if not isinstance(result, dict) or result.get('error') == 'not_found':
        raise Exception(f'Could not resolve the dropdown element at label {index}')
    if result.get('error') == 'not_select':
        tag = result.get('tag', 'unknown')
        raise Exception(f'Element at label {index} is a <{tag}>, not a <select> dropdown — use click_tool to open custom dropdowns')
    not_found = result.get('notFound', [])
    if not_found:
        raise Exception(f"Could not find option(s) {not_found} in dropdown at label {index}. Available options: {result.get('available', [])}")
    return f"Selected {', '.join(result.get('selected', []))} in element at label {index}"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `uv run pytest tests/test_menu_tool.py -v`
Expected: all 8 tests PASS

- [ ] **Step 5: Commit**

```bash
git add tests/test_menu_tool.py src/agent/tools/service.py docs/superpowers/plans/2026-07-04-dropdown-select-tool.md
git commit -m "feat: surface dropdown selection failures to the agent with available options"
```

---

### Task 4: `select_option_at` parity + full-suite verification

**Files:**
- Modify: `src/agent/browser/page.py:229-243` (the `select_option_at` method)
- Modify: `src/agent/browser/service.py:920-921` (the `select_option_at` delegate)
- Test: `tests/test_menu_tool.py` (append)

**Interfaces:**
- Consumes: `Page.execute_script(script, truncate=False, repair=False) -> Any` (existing).
- Produces: `Page.select_option_at(x, y, labels) -> dict` and `Browser.select_option_at(x, y, labels) -> dict`, same three result shapes as Task 2 (element located via `elementFromPoint` + `SELECT`-ancestor walk instead of xpath). No tool consumes this today; parity prevents the two code paths from drifting.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_menu_tool.py`:

```python
def test_select_option_at_returns_structured_result():
    from src.agent.browser.page import Page
    page = Page.__new__(Page)
    page.execute_script = AsyncMock(return_value={'error': 'not_found'})
    result = asyncio.run(page.select_option_at(10, 20, ['BMW']))
    assert result == {'error': 'not_found'}
    script = page.execute_script.call_args.args[0]
    assert 'elementFromPoint(10, 20)' in script
    assert json.dumps(['BMW']) in script
    assert 'not_select' in script
```

- [ ] **Step 2: Run test to verify it fails**

Run: `uv run pytest tests/test_menu_tool.py::test_select_option_at_returns_structured_result -v`
Expected: FAIL (`result` is `None` and the current script has no `not_select` marker).

- [ ] **Step 3: Rewrite both `select_option_at` methods**

In `src/agent/browser/page.py`, replace the `select_option_at` method (currently lines 229–243) with:

```python
    async def select_option_at(self, x: int, y: int, labels: list[str]) -> dict:
        labels_json = json.dumps(labels)
        return await self.execute_script(
            f'(function(){{'
            f'  var start = document.elementFromPoint({x}, {y});'
            f'  if (!start) return {{error: "not_found"}};'
            f'  var el = start;'
            f'  while (el && el.tagName !== "SELECT") el = el.parentElement;'
            f'  if (!el) return {{error: "not_select", tag: start.tagName.toLowerCase()}};'
            f'  var labels = {labels_json};'
            f'  var texts = Array.from(el.options).map(function(o){{ return o.text.trim(); }});'
            f'  var selected = labels.filter(function(l){{ return texts.indexOf(l) >= 0; }});'
            f'  var notFound = labels.filter(function(l){{ return texts.indexOf(l) < 0; }});'
            f'  if (selected.length) {{'
            f'    if (el.multiple) {{'
            f'      for (var i = 0; i < el.options.length; i++) el.options[i].selected = labels.indexOf(texts[i]) >= 0;'
            f'    }} else {{'
            f'      el.selectedIndex = texts.indexOf(selected[0]);'
            f'    }}'
            f'    el.dispatchEvent(new Event("input", {{bubbles: true}}));'
            f'    el.dispatchEvent(new Event("change", {{bubbles: true}}));'
            f'  }}'
            f'  return {{selected: selected, notFound: notFound, available: texts.slice(0, 30)}};'
            f'}})()'
        )
```

In `src/agent/browser/service.py`, replace the `select_option_at` delegate (currently lines 920–921) with:

```python
    async def select_option_at(self, x: int, y: int, labels: list[str]) -> dict:
        return await self.current_page().select_option_at(x, y, labels)
```

- [ ] **Step 4: Run the full test suite**

Run: `uv run pytest tests/ -v`
Expected: all tests PASS (9 in `test_menu_tool.py` plus the pre-existing `test_browser_attach.py` tests).

- [ ] **Step 5: Commit**

```bash
git add tests/test_menu_tool.py src/agent/browser/page.py src/agent/browser/service.py docs/superpowers/plans/2026-07-04-dropdown-select-tool.md
git commit -m "feat: bring select_option_at to parity with structured select_option result"
```
