import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_feature_documentpreview/src/html_body.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'file reload and interactive-mode changes retire the old HTML browsing context',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('app.kevinzhow.whalee/html');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final files = FakeWorkspaceFiles()..texts['a.html'] = '<h1>First</h1>';
      final document = DocumentController(
        sessionId: 'original',
        path: 'a.html',
        files: files,
      );
      Widget view(bool interactive) => dshTestApp(
        AnimatedBuilder(
          animation: document,
          builder: (context, _) => document.bytes == null
              ? const SizedBox()
              : HtmlBody(
                  document: document,
                  i18n: const DshI18n(DshLocale.en),
                  interactive: interactive,
                ),
        ),
      );
      await t.pumpWidget(view(false));
      await t.pumpAndSettle();
      final first =
          calls.where((c) => c.method == 'create').single.arguments as Map;
      expect(first['html'], contains('First'));
      files.texts['a.html'] = '<h1>Second</h1>';
      await document.reload();
      await t.pumpAndSettle();
      final second =
          calls.where((c) => c.method == 'create').last.arguments as Map;
      expect(second['html'], contains('Second'));
      expect(second['id'], isNot(first['id']));
      expect(
        calls
            .where((c) => c.method == 'dispose')
            .map((c) => (c.arguments as Map)['id']),
        contains(first['id']),
      );
      await t.pumpWidget(view(true));
      await t.pumpAndSettle();
      final interactive =
          calls.where((c) => c.method == 'create').last.arguments as Map;
      expect(interactive['html'], contains('sandbox="allow-scripts"'));
      expect(interactive['id'], isNot(second['id']));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      document.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
