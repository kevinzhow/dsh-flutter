import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

final Map<String, ParityCase> menuGeometryCases = {
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
