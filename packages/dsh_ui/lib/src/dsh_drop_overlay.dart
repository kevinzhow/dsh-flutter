import 'package:flutter/widgets.dart';

import 'dsh_file_types.dart';
import 'theme_access.dart';

/// The invitation shown over the window while a file is dragged onto it (dsh
/// `DropOverlay`): the drop mask, a title and, while drops are accepted, the
/// image limits line. Decoration only: it takes no pointer events, so the
/// drag keeps reaching the drop target below.
class DshDropOverlay extends StatelessWidget {
  const DshDropOverlay({super.key, required this.title, this.desc});

  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return IgnorePointer(
      child: ColoredBox(
        key: const ValueKey('drop-overlay'),
        color: theme.color('--dsw-alias-bg-mask-drop'),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DshFileTypeIcon(kind: 'image', size: 56),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme
                      .textStyle('--dsw-font-l-20')
                      .copyWith(color: theme.labelPrimary),
                ),
                if (desc != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    desc!,
                    textAlign: TextAlign.center,
                    style: theme
                        .textStyle('--dsw-font-s-14')
                        .copyWith(
                          color: theme.color('--dsw-alias-label-tertiary'),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
