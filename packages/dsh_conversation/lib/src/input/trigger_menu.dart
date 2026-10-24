/// Menu reduction (dsh `ui-input-trigger` `core/menu`): one group per source,
/// generation-gated settlement, an empty ready roster auto-closes. Stale and
/// no-op events return the same state instance.
library;

import 'trigger_types.dart';

/// The closed rest state.
const MenuState menuClosed = MenuState();

/// Replace the group roster with pending groups for [sources], in order. The
/// shell calls it before dispatching `hit` on a fresh menu open.
MenuState seedGroups(
  MenuState state,
  List<({String name, bool showGroupTitle})> sources,
) => MenuState(
  open: state.open,
  hit: state.hit,
  generation: state.generation,
  groups: [
    for (final s in sources)
      MenuGroup(
        source: s.name,
        showGroupTitle: s.showGroupTitle,
        ready: false,
        items: const [],
      ),
  ],
  highlight: null,
);

MenuState _closed(MenuState state) =>
    state.open ||
        state.hit != null ||
        state.groups.isNotEmpty ||
        state.highlight != null
    ? MenuState(generation: state.generation)
    : state;

MenuHighlight? _firstHighlight(List<MenuGroup> groups) {
  for (final g in groups) {
    if (g.ready && g.items.isNotEmpty) return MenuHighlight(g.source, 0);
  }
  return null;
}

MenuHighlight? _validHighlight(MenuHighlight? h, List<MenuGroup> groups) {
  if (h == null) return null;
  for (final g in groups) {
    if (g.source == h.source) {
      return g.ready && h.index < g.items.length ? h : null;
    }
  }
  return null;
}

List<MenuHighlight> _positions(List<MenuGroup> groups) => [
  for (final g in groups)
    if (g.ready)
      for (var i = 0; i < g.items.length; i++) MenuHighlight(g.source, i),
];

bool _allReadyEmpty(List<MenuGroup> groups) =>
    groups.every((g) => g.ready && g.items.isEmpty);

/// The pure menu reducer.
MenuState menuReduce(MenuState state, MenuEvent ev) {
  switch (ev) {
    case MenuHit(:final hit):
      if (hit == null) return _closed(state);
      return MenuState(
        open: true,
        hit: hit,
        generation: state.generation + 1,
        // Rows and highlight survive a refinement (stale-while-revalidate);
        // pending status still fences picks off the stale rows.
        groups: [for (final g in state.groups) g.copyWith(ready: false)],
        highlight: state.highlight,
      );
    case MenuSourceSettled():
      if (!state.open || ev.generation != state.generation) return state;
      final idx = state.groups.indexWhere((g) => g.source == ev.source);
      if (idx < 0) return state;
      final groups = [
        for (var i = 0; i < state.groups.length; i++)
          i == idx
              ? state.groups[i].copyWith(ready: true, items: ev.items)
              : state.groups[i],
      ];
      if (_allReadyEmpty(groups)) return _closed(state);
      return MenuState(
        open: true,
        hit: state.hit,
        generation: state.generation,
        groups: groups,
        highlight:
            _validHighlight(state.highlight, groups) ?? _firstHighlight(groups),
      );
    case MenuSourceFailed():
      if (!state.open || ev.generation != state.generation) return state;
      if (!state.groups.any((g) => g.source == ev.source)) return state;
      final groups = [
        for (final g in state.groups)
          if (g.source != ev.source) g,
      ];
      if (groups.isEmpty || _allReadyEmpty(groups)) return _closed(state);
      return MenuState(
        open: true,
        hit: state.hit,
        generation: state.generation,
        groups: groups,
        highlight:
            _validHighlight(state.highlight, groups) ?? _firstHighlight(groups),
      );
    case MenuMove(:final dir):
      if (!state.open) return state;
      final pos = _positions(state.groups);
      if (pos.isEmpty) return state;
      final hl = state.highlight;
      final at = hl == null ? -1 : pos.indexOf(hl);
      final next =
          pos[at < 0
              ? (dir == 1 ? 0 : pos.length - 1)
              : (at + dir + pos.length) % pos.length];
      if (hl != null && next == hl) return state;
      return MenuState(
        open: true,
        hit: state.hit,
        generation: state.generation,
        groups: state.groups,
        highlight: next,
      );
    case MenuHover(:final source, :final index):
      if (!state.open) return state;
      final target = _validHighlight(
        MenuHighlight(source, index),
        state.groups,
      );
      if (target == null) return state;
      if (state.highlight == target) return state;
      return MenuState(
        open: true,
        hit: state.hit,
        generation: state.generation,
        groups: state.groups,
        highlight: target,
      );
    case MenuClose():
      return _closed(state);
  }
}

/// The candidate named [name] in [source]'s ready group, or null.
InputTriggerCandidate? exactMatch(
  List<MenuGroup> groups,
  String source,
  String name,
) {
  for (final g in groups) {
    if (g.source != source) continue;
    if (!g.ready) return null;
    for (final c in g.items) {
      if (c.name == name) return c;
    }
    return null;
  }
  return null;
}
