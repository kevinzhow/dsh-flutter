/// Validated current-layout snapshots. Undo history stays in the live window.
library;

import 'types.dart';

class SavedDockLayout {
  const SavedDockLayout(this.layout, this.minted);
  final LayoutState layout;
  final int minted;

  Map<String, Object?> toJson() => {
    'minted': minted,
    'layout': {
      'nodes': {
        for (final entry in layout.nodes.entries)
          entry.key: switch (entry.value) {
            PaneNode(
              :final id,
              :final host,
              :final tabs,
              :final activeTabId,
              :final rect,
            ) =>
              {
                'kind': 'pane',
                'id': id,
                'host': host.name,
                'tabs': tabs,
                if (activeTabId != null) 'activeTabId': activeTabId,
                if (rect != null)
                  'rect': {
                    'x': rect.x,
                    'y': rect.y,
                    'width': rect.width,
                    'height': rect.height,
                  },
              },
            SplitNode(:final id, :final axis, :final children, :final sizes) =>
              {
                'kind': 'split',
                'id': id,
                'axis': axis.name,
                'children': children,
                'sizes': sizes,
              },
          },
      },
      'tabs': {
        for (final entry in layout.tabs.entries)
          entry.key: {
            'id': entry.value.id,
            'kind': entry.value.kind,
            'contentId': entry.value.contentId,
            'title': entry.value.title,
          },
      },
      'rootId': layout.rootId,
      'floats': layout.floats,
      'activePaneId': layout.activePaneId,
      'expanded': layout.expanded,
      'mode': layout.mode.name,
    },
  };

  /// Reject malformed identities, cycles, duplicate seats, dangling references
  /// and shapes outside the sidebar's two-pane contract before constructing UI.
  static SavedDockLayout? tryRead(Object? value) {
    try {
      return _read(value);
    } on FormatException {
      return null;
    }
  }

  static SavedDockLayout _read(Object? value) {
    Never invalid() => throw const FormatException('Invalid saved dock layout');
    Map<String, Object?> object(Object? v) =>
        v is Map<String, Object?> ? v : invalid();
    String text(Object? v) => v is String && v.length <= 8192 ? v : invalid();
    List<Object?> list(Object? v) =>
        v is List<Object?> && v.length <= 128 ? v : invalid();
    double number(Object? v) =>
        v is num && v.isFinite ? v.toDouble() : invalid();
    final saved = object(value), raw = object(saved['layout']);
    final minted = saved['minted'];
    if (minted is! int || minted < 1 || minted > 1000000000) invalid();
    String identity(Object? v, String pattern) {
      final id = text(v);
      if (!RegExp('^(?:$pattern)[1-9][0-9]*\$').hasMatch(id)) invalid();
      final counter = int.tryParse(id.replaceFirst(RegExp('^[a-z]+'), ''));
      if (counter == null || counter > minted) invalid();
      return id;
    }

    final rawNodes = object(raw['nodes']), rawTabs = object(raw['tabs']);
    if (rawNodes.isEmpty || rawNodes.length > 66 || rawTabs.length > 128) {
      invalid();
    }
    final nodes = <String, LayoutNode>{}, tabs = <String, TabRecord>{};
    for (final entry in rawNodes.entries) {
      final node = object(entry.value), kind = node['kind'];
      final id = identity(node['id'], kind == 'split' ? 'split' : 'pane|float');
      if (id != entry.key) invalid();
      if (kind == 'pane') {
        final host = switch (node['host']) {
          'dock' => PaneHost.dock,
          'float' => PaneHost.float,
          _ => invalid(),
        };
        final ids = list(node['tabs'])
            .map((v) => TabId(identity(v, 'tab')))
            .toList();
        final active = node['activeTabId'] == null
            ? null
            : TabId(identity(node['activeTabId'], 'tab'));
        final r = node['rect'];
        FloatRect? rect;
        if (r != null) {
          final m = object(r);
          rect = FloatRect(
            number(m['x']),
            number(m['y']),
            number(m['width']),
            number(m['height']),
          );
          if (rect.width <= 0 || rect.height <= 0) invalid();
        }
        nodes[id] = PaneNode(
          paneId: PaneId(id),
          host: host,
          tabs: ids,
          activeTabId: active,
          rect: rect,
        );
      } else if (kind == 'split') {
        final axis = switch (node['axis']) {
          'row' => SplitAxis.row,
          'column' => SplitAxis.column,
          _ => invalid(),
        };
        nodes[id] = SplitNode(
          splitId: SplitId(id),
          axis: axis,
          children: list(node['children'])
              .map((v) => identity(v, 'pane|float|split'))
              .toList(),
          sizes: list(node['sizes']).map(number).toList(),
        );
      } else {
        invalid();
      }
    }
    for (final entry in rawTabs.entries) {
      final record = object(entry.value), id = identity(record['id'], 'tab');
      if (id != entry.key) invalid();
      final kind = text(record['kind']), contentId = text(record['contentId']);
      if (kind.isEmpty || contentId.isEmpty) invalid();
      tabs[id] = TabRecord(
        id: TabId(id),
        kind: kind,
        contentId: contentId,
        title: text(record['title']),
      );
    }
    final root = identity(raw['rootId'], 'pane|split'),
        active = identity(raw['activePaneId'], 'pane|float');
    final floats = list(raw['floats'])
        .map((v) => PaneId(identity(v, 'pane|float')))
        .toList();
    final expanded = raw['expanded'];
    if (expanded is! bool) invalid();
    final mode = switch (raw['mode']) {
      'push' => DockMode.push,
      'fullscreen' => DockMode.fullscreen,
      _ => invalid(),
    };
    final visited = <String>{}, usedTabs = <String>{};
    final pending = [
      (root, PaneHost.dock),
      for (final id in floats) (id, PaneHost.float),
    ];
    for (var cursor = 0; cursor < pending.length; cursor++) {
      final (id, host) = pending[cursor];
      final node = nodes[id];
      if (!visited.add(id) || node == null) invalid();
      if (node is SplitNode) {
        if (host != PaneHost.dock ||
            id != root ||
            node.axis != SplitAxis.row ||
            node.children.length != 2 ||
            node.sizes.length != 2 ||
            node.sizes.any((n) => n <= 0) ||
            (node.sizes.reduce((a, b) => a + b) - 1).abs() > 1e-9) {
          invalid();
        }
        pending.addAll(node.children.map((id) => (id, host)));
      } else if (node is PaneNode) {
        if (node.host != host ||
            (host == PaneHost.float
                ? (node.rect == null || node.tabs.length != 1)
                : node.rect != null)) {
          invalid();
        }
        if (node.tabs.isEmpty
            ? node.activeTabId != null
            : !node.tabs.contains(node.activeTabId)) {
          invalid();
        }
        for (final tab in node.tabs) {
          if (!usedTabs.add(tab) || !tabs.containsKey(tab)) invalid();
        }
      }
    }
    if (visited.length != nodes.length ||
        usedTabs.length != tabs.length ||
        nodes[active] is! PaneNode) {
      invalid();
    }
    return SavedDockLayout(
      LayoutState(
        nodes: nodes,
        tabs: tabs,
        rootId: root,
        floats: floats,
        activePaneId: PaneId(active),
        expanded: expanded,
        mode: mode,
      ),
      minted,
    );
  }
}
