import 'dart:convert';
import 'dart:io';

import 'package:dsh_conversation/src/user_text/credentials.dart';
import 'package:dsh_conversation/src/user_text/document.dart';
import 'package:dsh_conversation/src/user_text/reference_rules.dart';
import 'package:test/test.dart';

String expand(List<dynamic> parts) => parts
    .map(
      (p) => p is String
          ? p
          : List.filled(
              (p as Map)['count'] as int,
              p['repeat'] as String,
            ).join(),
    )
    .join();
Map<String, Object?> nodeJson(UserTextNode node) => {
  'id': node.id,
  'start': node.start,
  'end': node.end,
  'data': node.data,
};
UserTextRegistry registry() => UserTextRegistry()
  ..register(createSecretRule())
  ..register(fileReferenceRule)
  ..register(folderReferenceRule)
  ..register(sessionReferenceRule)
  ..register(trimWhitespaceRule)
  ..register(collapseWhitespaceRule);
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/user_text_behavior.json').readAsStringSync(),
  ) as Map;
  test(
    'sent references and masks match actual pinned document reconciliation',
    () {
      final documents = fixture['documents'] as List;
      final expected = (fixture['expected'] as Map)['documents'] as List;
      for (var i = 0; i < documents.length; i++) {
        final c = documents[i] as Map;
        final facts = Map<String, Object?>.from(c['facts'] as Map? ?? {});
        if (facts['sessionLabels'] case final List<dynamic> labels) {
          facts['sessionLabels'] = labels.cast<String>();
        }
        final actual = registry()
            .createDocument()
            .evaluate(expand(c['parts'] as List), facts: facts)
            .map(nodeJson)
            .toList();
        expect(actual, expected[i], reason: 'synthetic document $i');
      }
    },
  );
  test(
    'credential queries from every cursor use the production scanner ranges',
    () {
      final cases = fixture['queries'] as List;
      final expected = (fixture['expected'] as Map)['queries'] as List;
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i] as Map, scanner = CredentialScanner();
        final text = expand(c['parts'] as List);
        final actual = [
          for (final from in c['from'] as List)
            if (scanner.match(text, from as int) case final node?)
              nodeJson(node)
            else
              null,
        ];
        expect(
          actual,
          expected[i],
          reason: 'synthetic credential cursor case $i',
        );
      }
    },
  );
  test(
    'digit-free repeated prefixes do not trigger repeated suffix scanning',
    () {
      final text = List.filled(100000, 'sk-').join();
      final watch = Stopwatch()..start();
      expect(CredentialScanner().match(text, 0), isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    },
  );
}
