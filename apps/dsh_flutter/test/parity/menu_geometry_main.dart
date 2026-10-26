import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:dsh_feature_workspace/dsh_feature_workspace.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'plugins_preview_main.dart' as preview;

const _pages = <String, Widget>{
  'Dock': _DockScene(),
  'Workspaces': _WorkspaceScene(),
};

Widget menuGeometryFixture() =>
    const preview.Fixture(initialPage: 'Dock', extraPages: _pages);
Future<void> main() =>
    preview.runFixture(initialPage: 'Dock', extraPages: _pages);

const _labels = DockLabels(
  emptyPane: 'Empty pane',
  splitPane: 'Split pane',
  splitPaneDisabled: 'Pane limit',
  splitPaneNarrow: 'Too narrow',
  closeTab: 'Close tab',
  addTab: 'Add tab',
  dropZone: {
    DockZone.center: 'Move here',
    DockZone.left: 'Left',
    DockZone.right: 'Right',
    DockZone.top: 'Top',
    DockZone.bottom: 'Bottom',
  },
);

class _DockScene extends StatefulWidget {
  const _DockScene();
  @override
  State<_DockScene> createState() => _DockSceneState();
}

class _DockSceneState extends State<_DockScene> {
  late final controller = DockController(
    DockControllerOptions(
      makeInitialTab: (id) => TabRecord(
        id: id,
        kind: 'synthetic',
        contentId: 'synthetic-tab',
        title: 'Synthetic tab',
      ),
    ),
  )..setExpanded(true);
  @override
  Widget build(BuildContext context) => DockLayout(
    controller: controller,
    labels: _labels,
    renderTab: (_, tab) => Center(child: Text('Synthetic body: ${tab.title}')),
  );
}

class _WorkspaceScene extends StatefulWidget {
  const _WorkspaceScene();
  @override
  State<_WorkspaceScene> createState() => _WorkspaceSceneState();
}

class _WorkspaceSceneState extends State<_WorkspaceScene> {
  final link = LayerLink();
  final portal = OverlayPortalController();
  bool open = false, longList = false;
  void show(bool value) {
    setState(() => open = value);
    if (value) {
      portal.show();
    } else {
      portal.hide();
    }
  }

  String selected = 'alpha';
  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: portal,
    overlayChildBuilder: (context) => Positioned.fill(
      child: PickerMenu(
        link: link,
        rows: [
          const PickerRow(
            id: 'alpha',
            label: 'Alpha',
            icon: DshIcons.folderClose,
          ),
          const PickerRow(
            id: 'beta',
            label: 'Beta',
            icon: DshIcons.folderClose,
          ),
          if (longList)
            for (var i = 0; i < 40; i++)
              PickerRow(
                id: 'w$i',
                label: 'Workspace ${i.toString().padLeft(2, '0')}',
                icon: DshIcons.folderClose,
              ),
        ],
        footer: const [
          PickerRow(id: 'add', label: 'Add workspace', icon: DshIcons.plus),
        ],
        selectedId: selected,
        onSelect: (id) {
          setState(() => selected = id);
          show(false);
        },
        onClose: () => show(false),
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          left: 24,
          top: 24,
          child: CompositedTransformTarget(
            link: link,
            child: DshButton(
              onPressed: () => show(!open),
              child: const Text('Choose workspace'),
            ),
          ),
        ),
        Positioned(
          left: 24,
          top: 82,
          child: Text('Selected workspace: $selected'),
        ),
        Positioned(
          left: 220,
          top: 24,
          child: DshButton(
            onPressed: () => setState(() => longList = !longList),
            child: const Text('Long list'),
          ),
        ),
      ],
    ),
  );
}
