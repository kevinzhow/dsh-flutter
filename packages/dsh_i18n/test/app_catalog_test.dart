import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:test/test.dart';

void main() {
  test('every app string has English and Chinese text', () {
    for (final e in appCatalog.entries) {
      expect(e.value.en.trim(), isNotEmpty, reason: '${e.key} en');
      expect(e.value.zh, isNotNull, reason: '${e.key} has no zh');
      expect(e.value.zh!.trim(), isNotEmpty, reason: '${e.key} zh');
    }
  });

  test('placeholders agree between the two languages', () {
    final name = RegExp(r'\{(\w+)\}');
    for (final e in appCatalog.entries) {
      final en = name.allMatches(e.value.en).map((m) => m[1]).toSet();
      final zh = name.allMatches(e.value.zh!).map((m) => m[1]).toSet();
      expect(zh, en, reason: '${e.key} placeholders');
    }
  });

  test('the default lookup reaches the app namespace', () {
    expect(
      const DshI18n(DshLocale.en).t(appNamespace, 'sessions.title'),
      'Sessions',
    );
    expect(const DshI18n(DshLocale.zh).t(appNamespace, 'sessions.title'), '会话');
  });

  test('app keys do not shadow dsh namespaces', () {
    expect(dshCatalog.containsKey(appNamespace), isFalse);
  });
}
