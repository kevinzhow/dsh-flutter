import 'package:dsh_feature_chat/src/stream/jump_button.dart';
import 'package:dsh_feature_chat/src/stream/row_extents.dart';
import 'package:dsh_feature_chat/src/stream/skeleton.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// The skeleton follows raft-flutter's skeleton_test (pulse, reduced motion);
// the button's states are dsh's `.toBottom` plus Raft's "N new" label.

void main() {
  testWidgets('the skeleton pulses, and holds still under reduced motion', (
    t,
  ) async {
    await t.pumpWidget(dshTestApp(const StreamSkeleton()));
    expect(t.binding.transientCallbackCount, greaterThan(0));
    final opacities = <double>{};
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
      for (final o in t.widgetList<Opacity>(find.byType(Opacity))) {
        opacities.add(o.opacity);
      }
    }
    expect(opacities.length, greaterThan(3), reason: 'it did not pulse');
    expect(opacities.reduce((a, b) => a < b ? a : b), closeTo(.5, .05));
    await t.pumpWidget(
      dshTestApp(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: StreamSkeleton(),
        ),
      ),
    );
    await t.pump();
    expect(t.binding.transientCallbackCount, 0);
  });

  testWidgets('the back-to-bottom control: chevron alone, or a count pill', (
    t,
  ) async {
    var taps = 0;
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: StreamJumpButton(
            label: 'Back to bottom',
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    expect(t.getSize(find.byKey(const ValueKey('chat-to-bottom'))).height, 44);
    expect(find.byKey(const ValueKey('chat-new-count')), findsNothing);
    await t.tap(find.byKey(const ValueKey('chat-to-bottom')));
    expect(taps, 1);
    await t.pumpWidget(
      dshTestApp(
        Center(
          child: StreamJumpButton(
            label: 'Back to bottom',
            countLabel: '3 new',
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('3 new'), findsOneWidget);
    await t.tap(find.text('3 new'));
    expect(taps, 2);
  });

  test(
    'row extents remember a measurement only for the width it was made at',
    () {
      final extents = RowExtents(limit: 2);
      extents.record('a', 400, 120);
      expect(extents.measured('a', 400), 120);
      expect(extents.measured('a', 300), isNull);
      extents.record('b', 400, 80);
      extents.record('c', 400, 60);
      expect(
        extents.measured('a', 400),
        isNull,
        reason: 'the oldest is evicted',
      );
      expect(extents.length, 2);
    },
  );
}
