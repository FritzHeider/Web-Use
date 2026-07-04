# Memories

## Patterns

### mem-1783145929-4d18
> menu_tool now raises Exception on select_option failure shapes (not_found/not_select/notFound) instead of always claiming success; Registry.aexecute converts raised exceptions to ToolResult(is_success=False), which is how the agent loop sees failed dropdown selections.
<!-- tags: dropdown, menu-tool, error-handling | created: 2026-07-04 -->

## Decisions

## Fixes

### mem-1783145690-c644
> uv run pytest failed with ModuleNotFoundError: No module named 'src' and used conda python — pytest wasn't installed in .venv (dev deps not synced). Fix: run 'uv sync --extra dev' once, then 'uv run pytest ...' uses .venv correctly.
<!-- tags: testing, pytest, venv | created: 2026-07-04 -->

## Context

### mem-1783146084-877c
> Plan's stop condition was narrowed mid-run (uncommitted edit found in the plan file, not authored this iteration) to scope pytest verification to tests/test_menu_tool.py instead of the full tests/ dir, explicitly excusing the 6 pre-existing test_browser_attach.py failures (missing pytest-asyncio, out of scope per 'no new deps' constraint). All 9 test_menu_tool.py tests pass; Task 4 (select_option_at parity) committed as 74fe436.
<!-- tags: dropdown, menu-tool, testing | created: 2026-07-04 -->

### mem-1783145825-3cc3
> tests/test_browser_attach.py has 6 pre-existing failures (PytestUnknownMarkWarning on @pytest.mark.asyncio) unrelated to dropdown-select-tool work — no pytest-asyncio plugin installed. Confirmed via git stash that failures predate Task 2 changes.
<!-- tags: testing, pytest, pre-existing-failure | created: 2026-07-04 -->
