import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:dsh_feature_workspace/dsh_feature_workspace.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'plugins_preview_main.dart' as preview;

Future<void> main() => preview.runFixture(
  initialPage: 'Dock',
  extraPages: const {'Dock': _DockScene(), 'Workspaces': _WorkspaceScene()},
);

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
  bool open = false;
  String selected = 'alpha';
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: 24,
        top: 24,
        child: CompositedTransformTarget(
          link: link,
          child: DshButton(
            onPressed: () => setState(() => open = !open),
            child: const Text('Choose workspace'),
          ),
        ),
      ),
      Positioned(
        left: 24,
        top: 82,
        child: Text('Selected workspace: $selected'),
      ),
      if (open)
        Positioned(
          left: 0,
          top: 0,
          child: PickerMenu(
            link: link,
            rows: const [
              PickerRow(
                id: 'alpha',
                label: 'Alpha',
                icon: DshIcons.folderClose,
              ),
              PickerRow(id: 'beta', label: 'Beta', icon: DshIcons.folderClose),
            ],
            footer: const [
              PickerRow(id: 'add', label: 'Add workspace', icon: DshIcons.plus),
            ],
            selectedId: selected,
            onSelect: (id) => setState(() {
              selected = id;
              open = false;
            }),
            onClose: () => setState(() => open = false),
          ),
        ),
    ],
  );
}
