import asyncio
from unittest.mock import AsyncMock, MagicMock

from src.agent.dom.service import DOM
from src.agent.dom.views import BoundingBox, CenterCord, DOMNode


def _interactive(idx: int, name: str) -> DOMNode:
    return DOMNode(
        tag='button',
        role='button',
        element_type='interactive',
        name=name,
        interactive_id=idx,
        center=CenterCord(x=10 * idx, y=10 * idx),
        bounding_box=BoundingBox(left=idx, top=idx, width=10, height=10),
        xpath={'frame': '', 'element': f'/button[{idx + 1}]'},
        viewport=(1280, 720),
    )


def _dom(nodes: list[DOMNode], coverage):
    """A DOM whose _parse yields `nodes` and whose coverage check returns `coverage`.

    `coverage` is either the list the page JS would return, or an Exception to raise.
    """
    tree_root = DOMNode(tag='document', role='document', element_type='structural')
    for node in nodes:
        tree_root.add_child(node)

    def execute_script(script, *args, **kwargs):
        if script.startswith('window.devicePixelRatio'):
            return 1.0
        if isinstance(coverage, Exception):
            raise coverage
        return coverage

    session = MagicMock()
    session._wait_for_page = AsyncMock()
    session._get_current_session_id = MagicMock(return_value='session-1')
    session.send = AsyncMock(return_value={})
    session.get_viewport = AsyncMock(return_value=(1280, 720))
    session.get_scroll_position = AsyncMock(return_value={'scrollX': 0, 'scrollY': 0})
    session.execute_script = AsyncMock(side_effect=execute_script)

    dom = DOM(session)
    dom._parse = MagicMock(return_value=(nodes, [], [], tree_root))
    return dom


def _state(nodes, coverage):
    _, state = asyncio.run(_dom(nodes, coverage).get_state(use_vision=False))
    return state


def test_interactive_ids_are_reindexed_after_visibility_filtering():
    nodes = [_interactive(i, n) for i, n in enumerate('ABCD')]

    state = _state(nodes, [True, False, True, True])

    assert [n.name for n in state.interactive_nodes] == ['A', 'C', 'D']
    assert [n.interactive_id for n in state.interactive_nodes] == [0, 1, 2]


def test_covered_nodes_are_demoted_to_structural():
    nodes = [_interactive(i, n) for i, n in enumerate('ABCD')]
    dropped = nodes[1]

    _state(nodes, [True, False, True, True])

    assert dropped.interactive_id is None
    assert dropped.element_type == 'structural'


def test_selector_map_agrees_with_reindexed_ids():
    # get_element_by_index looks elements up positionally, so selector_map[i]
    # must be the node whose interactive_id is i.
    nodes = [_interactive(i, n) for i, n in enumerate('ABCD')]

    state = _state(nodes, [True, False, True, True])

    for index, node in state.selector_map.items():
        assert node.interactive_id == index
        assert node is state.interactive_nodes[index]


def test_tree_labels_match_selector_map():
    # The regression: [#N] labels are rendered from interactive_id, so a
    # desynced id makes the agent click the wrong element.
    nodes = [_interactive(i, n) for i, n in enumerate('ABCD')]

    state = _state(nodes, [True, False, True, True])
    tree = state.semantic_tree_to_string()

    for index, node in state.selector_map.items():
        assert f'[#{index}] button "{node.name}"' in tree
    # The covered node lost its label but stays in the tree as context.
    assert 'button "B"' in tree
    assert '[#' not in [line for line in tree.splitlines() if '"B"' in line][0]


def test_ids_unchanged_when_everything_is_visible():
    nodes = [_interactive(i, n) for i, n in enumerate('ABCD')]

    state = _state(nodes, [True, True, True, True])

    assert [n.name for n in state.interactive_nodes] == ['A', 'B', 'C', 'D']
    assert [n.interactive_id for n in state.interactive_nodes] == [0, 1, 2, 3]


def test_coverage_failure_keeps_every_node():
    nodes = [_interactive(i, n) for i, n in enumerate('ABCD')]

    state = _state(nodes, RuntimeError('page navigated away'))

    assert [n.name for n in state.interactive_nodes] == ['A', 'B', 'C', 'D']
    assert [n.interactive_id for n in state.interactive_nodes] == [0, 1, 2, 3]


def test_mismatched_coverage_length_is_ignored():
    nodes = [_interactive(i, n) for i, n in enumerate('ABCD')]

    state = _state(nodes, [True, False])

    assert [n.name for n in state.interactive_nodes] == ['A', 'B', 'C', 'D']
    assert [n.interactive_id for n in state.interactive_nodes] == [0, 1, 2, 3]
