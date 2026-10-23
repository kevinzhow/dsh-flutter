import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decodes every [Image] currently in the tree (the counterpart of the React host waiting for its images): memory
/// images decode asynchronously, which a widget test only sees when the decode runs outside the fake clock.
Future<void> precacheTreeImages(WidgetTester tester) async {
  final images = find.byType(Image).evaluate().toList();
  if (images.isEmpty) return;
  await tester.runAsync(() async {
    for (final element in images) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}
