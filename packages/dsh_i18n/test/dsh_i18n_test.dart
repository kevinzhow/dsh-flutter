import 'dart:convert';
import 'dart:io';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:test/test.dart';

/// Packages the first UI ports depend on. ui-session and ui-primitives have no
/// dictionary in dsh 0.2.1-rc.2 (documented in the catalog header).
const mandatoryNamespaces = {
  'approval': 'client/ui-approval',
  'settings.theme': 'client/ui-theme',
  'settings': 'client/ui-settings-general',
  'conversation': 'client/ui-conversation',
  'common': 'client/locale',
};

void main() {
  const en = DshI18n(DshLocale.en);
  const zh = DshI18n(DshLocale.zh);

  group('lookup', () {
    test('returns the text of the active locale', () {
      expect(en.t('approval', 'allowOnce'), 'Allow once');
      expect(zh.t('approval', 'allowOnce'), '允许一次');
      expect(en.t('common', 'cancel'), 'Cancel');
    });

    test('falls back to the common namespace, then to the key', () {
      expect(en.t('approval', 'cancel'), 'Cancel');
      expect(zh.t('approval', 'close'), isNot('close'));
      expect(en.t('approval', 'no.such.key'), 'no.such.key');
      expect(en.t('no.such.namespace', 'no.such.key'), 'no.such.key');
      expect(en.has('approval', 'cancel'), isFalse);
      expect(en.has('common', 'cancel'), isTrue);
    });

    test('zh falls back to en for a gap, en has no fallback', () {
      const catalog = {
        'ns': {
          'both': (en: 'Both', zh: '两者'),
          'gap': (en: 'Only English', zh: null),
        },
      };
      const x = DshI18n(DshLocale.zh, catalog: catalog);
      expect(x.t('ns', 'both'), '两者');
      expect(x.t('ns', 'gap'), 'Only English');
      expect(x.withLocale(DshLocale.en).t('ns', 'both'), 'Both');
      expect(x.withLocale(DshLocale.en).locale, DshLocale.en);
    });

    test('bind returns a namespace translator', () {
      final t = zh.bind('approval');
      expect(t('reject'), '拒绝');
      expect(t('escalation', params: {'toolName': 'bash'}), '工具 bash 请求越权执行');
    });

    test('locale tags map to the two shipped locales', () {
      expect(DshLocale.fromTag('zh-CN'), DshLocale.zh);
      expect(DshLocale.fromTag('zh_Hans'), DshLocale.zh);
      expect(DshLocale.fromTag('ZH'), DshLocale.zh);
      expect(DshLocale.fromTag('en-US'), DshLocale.en);
      expect(DshLocale.fromTag('ja'), DshLocale.en);
    });
  });

  group('interpolation (dsh syntax: {word} only)', () {
    test('replaces named placeholders', () {
      expect(
        en.t('approval', 'escalation', params: {'toolName': 'bash'}),
        'Tool bash requests privileged execution',
      );
    });

    test('leaves placeholders without a param verbatim', () {
      expect(en.t('approval', 'escalation'), contains('{toolName}'));
      expect(DshI18n.interpolate('{a} and {b}', {'a': 1}), '1 and {b}');
    });

    test('stringifies like JavaScript String()', () {
      expect(DshI18n.interpolate('{n}', {'n': 3.0}), '3');
      expect(DshI18n.interpolate('{n}', {'n': 2.5}), '2.5');
      expect(DshI18n.interpolate('{n}', {'n': null}), 'null');
      expect(DshI18n.interpolate('{n}{n}', {'n': 'x'}), 'xx');
    });

    test('is not ICU: braces with spaces or commas are left alone', () {
      expect(
        DshI18n.interpolate('{n, plural, one {a} other {b}}', {'n': 1}),
        '{n, plural, one {a} other {b}}',
      );
    });

    test('dsh pluralises by key suffix, which works through t()', () {
      expect(
        en.t(
          'workspace',
          'archive.confirm.jobs.other',
          params: {'n': 2, 'names': 'a, b'},
        ),
        isNot(contains('{n}')),
      );
      expect(en.has('workspace', 'archive.confirm.jobs.one'), isTrue);
      expect(en.has('workspace', 'archive.confirm.jobs.other'), isTrue);
    });
  });

  group('catalog', () {
    test('covers the mandatory namespaces and packages', () {
      for (final e in mandatoryNamespaces.entries) {
        expect(dshCatalog, contains(e.key), reason: e.key);
        expect(dshCatalogPackages[e.key], e.value);
        expect(dshCatalog[e.key], isNotEmpty);
      }
      expect(dshCatalog.length, greaterThanOrEqualTo(20));
    });

    test('every en key has a zh value, except gaps in known-gaps.json', () {
      final gaps = <String>{
        for (final g
            in (jsonDecode(
                  File('../../tool/i18n/known-gaps.json').readAsStringSync(),
                ) as Map<String, Object?>)['gaps']
                as List)
          '${(g as Map)['namespace']}.${g['key']}.${g['missing']}',
      };
      final missing = <String>[];
      for (final ns in dshCatalog.entries) {
        for (final k in ns.value.entries) {
          if (k.value.zh == null && !gaps.contains('${ns.key}.${k.key}.zh')) {
            missing.add('${ns.key}.${k.key} (zh)');
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('en and zh use the same placeholders', () {
      final ph = RegExp(r'\{(\w+)\}');
      final bad = <String>[];
      for (final ns in dshCatalog.entries) {
        for (final k in ns.value.entries) {
          final z = k.value.zh;
          if (z == null) continue;
          final a = ph.allMatches(k.value.en).map((m) => m[1]).toSet();
          final b = ph.allMatches(z).map((m) => m[1]).toSet();
          if (a.length != b.length || !a.containsAll(b)) {
            bad.add('${ns.key}.${k.key}');
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('zh text is actually Chinese for the mandatory approval keys', () {
      final han = RegExp(r'[一-鿿]');
      for (final k in dshCatalog['approval']!.entries) {
        expect(han.hasMatch(k.value.zh!), isTrue, reason: k.key);
      }
    });
  });
}
