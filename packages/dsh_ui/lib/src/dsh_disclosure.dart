import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icons.g.dart';
import 'theme_access.dart';

/// A collapsible section: a tappable header row and a body shown while open
/// (dsh's `useDisclosure` rows such as reasoning and tool details).
class DshDisclosure extends StatefulWidget {
  const DshDisclosure({
    super.key,
    required this.header,
    required this.body,
    this.initiallyOpen = false,
    this.open,
    this.onToggle,
  });

  final Widget header;
  final Widget body;
  final bool initiallyOpen;

  /// When set, the section is controlled: it shows exactly this state and only
  /// reports taps through [onToggle].
  final bool? open;
  final ValueChanged<bool>? onToggle;

  @override
  State<DshDisclosure> createState() => _DshDisclosureState();
}

class _DshDisclosureState extends State<DshDisclosure> {
  late bool _internal = widget.initiallyOpen;
  bool get _open => widget.open ?? _internal;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final next = !_open;
              if (widget.open == null) setState(() => _internal = next);
              widget.onToggle?.call(next);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: DshSpace.touch - 8),
              child: Row(
                children: [
                  Expanded(child: widget.header),
                  DshIcon(
                    _open ? DshIcons.chevronUp : DshIcons.chevronDown,
                    size: 14,
                    color: theme.color('--dsw-alias-label-tertiary'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) widget.body,
      ],
    );
  }
}
