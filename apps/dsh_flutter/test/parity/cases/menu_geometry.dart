import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

DockLabels _labels(String close) => DockLabels(
  emptyPane: 'Empty pane',
  splitPane: 'Split pane',
  splitPaneDisabled: 'Pane limit',
  splitPaneNarrow: 'Too narrow',
  closeTab: close,
  addTab: 'Add tab',
  dropZone: {
    DockZone.center: 'Move here',
    DockZone.left: 'Left',
    DockZone.right: 'Right',
    DockZone.top: 'Top',
    DockZone.bottom: 'Bottom',
  },
);

class _DockScreen extends StatefulWidget {
  const _DockScreen({required this.width, required this.close});
  final double width;
  final String close;
  @override
  State<_DockScreen> createState() => _DockScreenState();
}

class _DockScreenState extends State<_DockScreen> {
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
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: 400,
    child: DockLayout(
      controller: controller,
      labels: _labels(widget.close),
      renderTab: (_, tab) => Center(
        child: DshChromeText(
          'Synthetic body',
          style: context.dsh.textStyle('--dsw-font-s-14'),
        ),
      ),
    ),
  );
}

final Map<String, ParityCase> menuGeometryCases = {
  'menu-geometry.screen': ParityCase(
    widgets: ['dsh_dockkit:DockLayout actual context menu'],
    build: (ctx) => _DockScreen(
      width: (ctx.props['width'] as num).toDouble(),
      close: ctx.props['label'] as String,
    ),
    interact: (t, ctx) async {
      await t.tap(find.text('Synthetic tab'), buttons: kSecondaryButton);
      await t.pump();
    },
  ),
  'menu-geometry.dock': ParityCase(
    widgets: ['dsh_ui:DshMenuSurface dock', 'dsh_ui:DshMenuItemButton dock'],
    build: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Focus(child: SizedBox(width: 120, height: 28)),
        const SizedBox(height: 4),
        DshMenuSurface(
          key: const ValueKey('dock-menu-surface'),
          profile: DshMenuSurfaceProfile.dock,
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DshMenuItemButton(
                  key: const ValueKey('dock-menu-close'),
                  profile: DshMenuItemProfile.dock,
                  label: ctx.props['label'] as String,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
};
