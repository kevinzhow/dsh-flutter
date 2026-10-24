import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:flutter/widgets.dart';

import 'terminal_body.dart';

/// The terminal's name in its tab chip (dsh `TerminalTitle`): the prompt glyph
/// and the live title, which the Host owns. A long press renames it (dsh: a
/// double click).
class TerminalTitle extends StatelessWidget {
  const TerminalTitle({
    super.key,
    required this.owner,
    required this.terminals,
    required this.i18n,
  });

  final SidebarTabOwner owner;
  final ClientTerminals terminals;
  final DshI18n i18n;

  @override
  Widget build(BuildContext context) {
    final view = terminalViewOf(terminals, owner);
    return StreamBuilder<TerminalViewState>(
      stream: view.state.changes,
      initialData: view.snapshot,
      builder: (context, snapshot) {
        final state = snapshot.data ?? view.snapshot;
        final title =
            state.info?.title ??
            state.title ??
            i18n.t('sidebarTerminal', 'title');
        final color = IconTheme.of(context).color ?? context.dsh.labelSecondary;
        return GestureDetector(
          key: const ValueKey('terminal-title'),
          behavior: HitTestBehavior.opaque,
          onLongPress: () => unawaited(_rename(context, view, title)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DshTerminalGlyph(size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: DshChromeText(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _rename(
    BuildContext context,
    TerminalView view,
    String current,
  ) async {
    final theme = context.dsh;
    final next = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.color('--dsw-alias-bg-layer-2'),
      builder: (sheet) => _RenameSheet(
        current: current,
        placeholder: i18n.t('sidebarTerminal', 'rename'),
      ),
    );
    final name = next?.trim();
    if (name != null &&
        name.isNotEmpty &&
        name.length <= 120 &&
        name != current) {
      await view.rename(name);
    }
  }
}

/// The name field of a terminal's rename sheet; it owns its controller so the
/// sheet can finish closing before the controller goes.
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.current, required this.placeholder});
  final String current;
  final String placeholder;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      DshSpace.lg,
      DshSpace.lg,
      DshSpace.lg,
      DshSpace.lg + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DshTextField(
          key: const ValueKey('terminal-rename'),
          controller: _controller,
          autofocus: true,
          placeholder: widget.placeholder,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ],
    ),
  );
}
