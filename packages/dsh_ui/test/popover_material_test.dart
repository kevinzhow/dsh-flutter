import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CSS backdrop mirror survives the saturation/blur composition', (
    tester,
  ) async {
    await tester.pumpWidget(
      dshTestApp(
        const Center(
          child: DshPopoverSurface(child: SizedBox(width: 300, height: 159)),
        ),
      ),
    );
    final filter = tester
        .widget<BackdropFilter>(find.byType(BackdropFilter))
        .filter;
    // The pinned engine materializes unspecified blur modes as clamp while
    // composing. Assert the source edge-mode contract at that API boundary;
    // the three real-source smoke pairs separately exercise rendered pixels.
    expect(filter.toString(), contains('mirror'));
    expect(filter.toString(), isNot(contains('unspecified')));
  });
}
