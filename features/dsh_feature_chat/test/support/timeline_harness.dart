import 'package:dsh_feature_chat/src/stream/timeline.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A timeline over plain rows, to test the engine without a session: row `i`
/// is `r<i>` and `heightOf(i)` tall. [prepend] adds older rows the way a page
/// landing does; [append] adds rows at the latest end.
class TimelineHarness extends StatefulWidget {
  TimelineHarness({
    super.key,
    this.first = 200,
    this.count = 50,
    double Function(int index)? heightOf,
    this.onLoadOlder,
    this.hasOlder = true,
    this.wide = false,
  }) : heightOf = heightOf ?? ((i) => 60.0 + (i % 5) * 20);

  /// Index of the oldest row at the start; rows `first..first+count-1`.
  final int first, count;
  final double Function(int index) heightOf;
  final VoidCallback? onLoadOlder;
  final bool hasOlder, wide;

  static HarnessState of(WidgetTester t) =>
      t.state<HarnessState>(find.byType(TimelineHarness));

  @override
  State<TimelineHarness> createState() => HarnessState();
}

class HarnessState extends State<TimelineHarness> {
  late List<int> rows = [
    for (var i = widget.first; i < widget.first + widget.count; i++) i,
  ];
  late final DshTimelineController controller = DshTimelineController(
    bottomAnchored: false,
  );
  bool loadingOlder = false;
  late String centerAfter = 'r${rows.last}';
  int epoch = 0;

  void prepend(int n) => setState(() {
    final oldest = rows.first;
    rows = [for (var i = oldest - n; i < oldest; i++) i, ...rows];
  });

  void append(int n) => setState(() {
    final last = rows.last;
    rows = [...rows, for (var i = last + 1; i <= last + n; i++) i];
  });

  /// Grows the height of the newest row (a streaming answer).
  double lastExtra = 0;
  void growLast(double by) => setState(() => lastExtra += by);

  void setLoading(bool v) => setState(() => loadingOlder = v);

  void recenter(int index, DshTimelineAlignment alignment) {
    setState(() {
      centerAfter = 'r${rows[index] - 1}';
      epoch++;
    });
    controller.align(alignment);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  int _indexOf(String id) => rows.indexWhere((r) => 'r$r' == id);

  @override
  Widget build(BuildContext context) {
    final ids = [for (final r in rows) 'r$r'];
    final center = (_indexOf(centerAfter) + 1).clamp(0, rows.length);
    return DshStreamTimeline(
      controller: controller,
      ids: ids,
      centerIndex: center,
      epoch: epoch,
      wide: widget.wide,
      indexOfId: (id) {
        final i = _indexOf(id);
        return i < 0 ? null : i;
      },
      estimateRow: (i) => widget.heightOf(rows[i]),
      rowBuilder: (context, i) => SizedBox(
        key: ValueKey('row-r${rows[i]}'),
        height:
            widget.heightOf(rows[i]) + (i == rows.length - 1 ? lastExtra : 0),
        child: Text('row ${rows[i]}'),
      ),
      slivers: (history, forward) => [
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        history,
        forward,
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
      hasOlder: widget.hasOlder,
      loadingOlder: loadingOlder,
      onLoadOlder: widget.onLoadOlder,
      onRecenter: (i, a) => recenter(i, a),
    );
  }
}

/// Where row `r<i>` is painted (global), or null when it is not built or
/// not on screen.
Rect? paintedRow(WidgetTester tester, int i) {
  final finder = find.byKey(ValueKey('row-r$i'));
  if (finder.evaluate().isEmpty) return null;
  final box = tester.renderObject<RenderBox>(finder);
  final Object? view = RenderAbstractViewport.maybeOf(box);
  if (view is! RenderBox) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final clip = view.localToGlobal(Offset.zero) & view.size;
  return rect.overlaps(clip) ? rect : null;
}

Widget timelineApp(Widget child, {Size? size}) =>
    dshTestApp(SizedBox.expand(child: child), size: size);
