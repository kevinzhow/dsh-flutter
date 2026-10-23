import 'package:flutter/widgets.dart';

/// The `layout` prop shared with the React host's `Stack` (tool/parity-web/host/layout.tsx).
class ParityLayout {
  /// Creates a layout.
  const ParityLayout({
    this.direction = Axis.horizontal,
    this.gap = 12,
    this.align = CrossAxisAlignment.start,
  });

  /// Reads `{direction: row|column, gap: n, align: start|center|end|stretch}`.
  factory ParityLayout.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ParityLayout();
    return ParityLayout(
      direction: json['direction'] == 'column'
          ? Axis.vertical
          : Axis.horizontal,
      gap: (json['gap'] as num?)?.toDouble() ?? 12,
      align: switch (json['align']) {
        'center' => CrossAxisAlignment.center,
        'end' => CrossAxisAlignment.end,
        'stretch' => CrossAxisAlignment.stretch,
        _ => CrossAxisAlignment.start,
      },
    );
  }

  /// Main axis.
  final Axis direction;

  /// Gap between children in logical px.
  final double gap;

  /// Cross-axis alignment.
  final CrossAxisAlignment align;
}

/// A flex row/column with a fixed gap: the Flutter twin of the host's `Stack`.
class ParityStack extends StatelessWidget {
  /// Creates a stack.
  const ParityStack({super.key, required this.layout, required this.children});

  /// Layout from the case props.
  final ParityLayout layout;

  /// Items, usually wrapped with [parityItem].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // A web flex container is a block: it fills the frame's content width (a column aligned to the end
      // puts its items at the right edge of that width).
      width: double.infinity,
      child: Flex(
        direction: layout.direction,
        spacing: layout.gap,
        crossAxisAlignment: layout.align,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Marks [child] as the element the manifest addresses as [id] (`data-parity-id` on the web) so
/// interactions can find it.
Widget parityItem(String id, Widget child) =>
    KeyedSubtree(key: ValueKey<String>(id), child: child);
