// Preference documents and conflict resolution (dsh `configuration.client.spec.ts`).
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:test/test.dart';

import 'support.dart';

final definitions = [
  ShortcutDefinition(
    id: 'test.one',
    defaults: {
      'desktop:macos': primary('KeyB'),
      'desktop:windows': primary('KeyB'),
      'desktop:linux': primary('KeyB'),
    },
  ),
  ShortcutDefinition(
    id: 'test.two',
    defaults: {
      'desktop:macos': primary('KeyJ'),
      'desktop:windows': primary('KeyJ'),
      'desktop:linux': primary('KeyJ'),
    },
  ),
];

List<List<String>> conflicts(
  List<ShortcutDefinition> defs,
  ShortcutDocument doc,
  ShortcutRuntime runtime,
  ShortcutPlatform platform,
) => [
  for (final row in effectiveShortcuts(defs, doc, runtime, platform))
    row.conflicts,
];

void main() {
  test(
    'distinguishes identical two-key chords from pairs sharing only one key',
    () {
      const left = NormalizedBinding('KeyA', [], 'KeyB');
      expect(
        overlappingBindings(left, const NormalizedBinding('KeyB', [], 'KeyA')),
        isTrue,
      );
      expect(
        overlappingBindings(left, const NormalizedBinding('KeyB', [], 'KeyC')),
        isFalse,
      );
    },
  );

  for (final platform in ShortcutPlatform.values) {
    test(
      'accepts Mod+Shift+Period on ${platform.name} without permitting shift-only Web bindings',
      () {
        final binding = normalizeBinding(
          const ShortcutBinding('Period', [
            ShortcutModifier.primary,
            ShortcutModifier.shift,
          ]),
          platform,
        );
        for (final runtime in ShortcutRuntime.values) {
          expect(bindingIssue(binding, runtime, platform), isNull);
        }
        for (final code in ['Period', 'F12', 'KeyJ']) {
          expect(
            bindingIssue(
              normalizeBinding(
                ShortcutBinding(code, [ShortcutModifier.shift]),
                platform,
              ),
              ShortcutRuntime.web,
              platform,
            ),
            BindingIssue.modifierRequired,
          );
        }
      },
    );
  }

  test('reserves the macOS Web control-command combination', () {
    expect(
      bindingIssue(
        const NormalizedBinding('KeyB', [
          ShortcutModifier.control,
          ShortcutModifier.meta,
        ]),
        ShortcutRuntime.web,
        ShortcutPlatform.macos,
      ),
      BindingIssue.reserved,
    );
  });

  group('preference document validation and conflict resolution', () {
    test('distinguishes inherited, cleared, reset, and dormant preferences without touching other profiles', () {
      final document = ShortcutDocument(
        schemaVersion: 1,
        profiles: {
          'desktop:macos': {
            'dormant.command': primary('KeyU'),
            'test.one': null,
          },
          'web:windows': {'test.one': primary('Slash')},
        },
      );
      expect(
        parseShortcutDocument(jsonOf(document)).document,
        equals(document),
      );
      final first = effectiveShortcuts(
        definitions,
        document,
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      )[0];
      expect((first.modified, first.binding), (true, null));
      final reset = editShortcutDocument(
        document,
        const ResetShortcut('test.one'),
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      );
      expect(reset.profiles['desktop:macos'], {
        'dormant.command': primary('KeyU'),
      });
      final back = effectiveShortcuts(
        definitions,
        reset,
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      )[0];
      expect((back.modified, back.binding?.code), (false, 'KeyB'));
      final resetAll = editShortcutDocument(
        document,
        const ResetAllShortcuts(),
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      );
      expect(resetAll.profiles, {
        'desktop:macos': <String, ShortcutBinding?>{},
        'web:windows': document.profiles['web:windows'],
      });
    });

    for (final raw in [
      '{',
      'null',
      '[]',
      '{"schemaVersion":0,"profiles":{}}',
      '{"schemaVersion":1,"profiles":{"alien":{}}}',
      '{"schemaVersion":1,"profiles":{"web:macos":{"bad":null}}}',
      '{"schemaVersion":1,"profiles":{},"extra":1}',
      '{"schemaVersion":1,"profiles":{"web:macos":{"test.one":{"code":"KeyB","modifiers":["bogus"]}}}}',
    ]) {
      test('retains invalid documents: $raw', () {
        expect(parseShortcutDocument(raw).error, ShortcutDocumentError.invalid);
      });
    }

    test('refuses future versions without interpreting their fields', () {
      expect(
        parseShortcutDocument('{"schemaVersion":3,"profiles":17}').error,
        ShortcutDocumentError.future,
      );
      expect(
        parseShortcutDocument(null).document,
        equals(const ShortcutDocument.empty()),
      );
      expect(
        () => parseBinding({
          'code': 'KeyB',
          'modifiers': ['primary'],
          'extra': true,
        }),
        throwsA(anything),
      );
      expect(
        () => parseBinding({'code': 'Unknown', 'modifiers': <String>[]}),
        throwsA(anything),
      );
    });

    test('lets explicit overrides displace new defaults, but disables both conflicting explicit overrides', () {
      final document = ShortcutDocument(
        schemaVersion: 1,
        profiles: {
          'desktop:windows': {'test.one': primary('KeyJ')},
        },
      );
      expect(
        conflicts(
          definitions,
          document,
          ShortcutRuntime.desktop,
          ShortcutPlatform.windows,
        ),
        [
          <String>[],
          ['test.one'],
        ],
      );
      final both = editShortcutDocument(
        document,
        const SetShortcut(
          'test.two',
          ShortcutBinding('KeyJ', [ShortcutModifier.control]),
        ),
        ShortcutRuntime.desktop,
        ShortcutPlatform.windows,
      );
      expect(
        conflicts(
          definitions.reversed.toList(),
          both,
          ShortcutRuntime.desktop,
          ShortcutPlatform.windows,
        ),
        [
          ['test.one'],
          ['test.two'],
        ],
      );
    });

    test('keeps Linux desktop and browser reservations', () {
      const platform = ShortcutPlatform.linux;
      BindingIssue? check(
        String code,
        List<ShortcutModifier> mods, [
        ShortcutRuntime runtime = ShortcutRuntime.desktop,
      ]) => bindingIssue(
        normalizeBinding(ShortcutBinding(code, mods), platform),
        runtime,
        platform,
      );
      const p = [ShortcutModifier.primary];
      for (final code in [
        'KeyC',
        'KeyV',
        'KeyX',
        'KeyZ',
        'KeyY',
        'KeyQ',
        'Tab',
        'Escape',
        'Space',
        'Enter',
      ]) {
        expect(check(code, p), BindingIssue.reserved, reason: code);
      }
      expect(
        check('KeyA', [ShortcutModifier.primary, ShortcutModifier.shift]),
        isNull,
      );
      expect(check('KeyA', p), BindingIssue.reserved);
      expect(check('KeyJ', []), BindingIssue.modifierRequired);
      expect(
        check('KeyJ', [ShortcutModifier.shift]),
        BindingIssue.modifierRequired,
      );
      expect(check('KeyJ', p), isNull);
      for (final code in ['KeyN', 'KeyP', 'KeyW', 'KeyR', 'KeyO', 'KeyJ']) {
        expect(
          check(code, p, ShortcutRuntime.web),
          BindingIssue.unsupportedBrowser,
          reason: code,
        );
      }
      for (final code in ['Comma', 'Period']) {
        expect(
          check(code, [
            ShortcutModifier.primary,
            ShortcutModifier.shift,
          ], ShortcutRuntime.web),
          isNull,
        );
      }
      expect(check('Slash', p, ShortcutRuntime.web), isNull);
      expect(check('F4', [ShortcutModifier.alt]), BindingIssue.reserved);
      expect(
        check('KeyL', [ShortcutModifier.meta, ShortcutModifier.control]),
        BindingIssue.reserved,
      );
    });

    for (final platform in [ShortcutPlatform.macos, ShortcutPlatform.windows]) {
      test(
        'accepts ${platform.name} desktop editing and system combinations, and single keys',
        () {
          for (final (code, mods) in [
            for (final c in [
              'KeyC',
              'KeyV',
              'KeyX',
              'KeyZ',
              'KeyY',
              'KeyA',
              'KeyQ',
              'KeyH',
              'Tab',
              'Space',
            ])
              (c, [ShortcutModifier.primary]),
            ('KeyC', [ShortcutModifier.control]),
            ('KeyX', [ShortcutModifier.control]),
            ('KeyN', [ShortcutModifier.shift]),
            ('Tab', [ShortcutModifier.control]),
            ('Tab', [ShortcutModifier.shift]),
            ('Escape', [ShortcutModifier.alt]),
            ('F4', [ShortcutModifier.alt]),
            ('KeyL', [ShortcutModifier.meta]),
            ('Delete', [ShortcutModifier.control, ShortcutModifier.alt]),
            ('KeyL', [ShortcutModifier.control, ShortcutModifier.meta]),
            ('ArrowLeft', [ShortcutModifier.alt]),
          ]) {
            expect(
              bindingIssue(
                normalizeBinding(ShortcutBinding(code, mods), platform),
                ShortcutRuntime.desktop,
                platform,
              ),
              isNull,
              reason: '$code $mods',
            );
          }
          expect(
            bindingIssue(
              normalizeBinding(const ShortcutBinding('KeyC'), platform),
              ShortcutRuntime.desktop,
              platform,
            ),
            isNull,
          );
          expect(
            bindingIssue(
              normalizeBinding(primary('KeyC'), platform),
              ShortcutRuntime.web,
              platform,
            ),
            BindingIssue.reserved,
          );
          var document = const ShortcutDocument.empty();
          for (final entry in definitions) {
            document = editShortcutDocument(
              document,
              SetShortcut(entry.id, primary('KeyC')),
              ShortcutRuntime.desktop,
              platform,
            );
          }
          expect(
            conflicts(definitions, document, ShortcutRuntime.desktop, platform),
            [
              ['test.two'],
              ['test.one'],
            ],
          );
        },
      );
    }

    for (final (runtime, platform) in [
      (ShortcutRuntime.web, ShortcutPlatform.macos),
      (ShortcutRuntime.web, ShortcutPlatform.windows),
      (ShortcutRuntime.desktop, ShortcutPlatform.macos),
      (ShortcutRuntime.desktop, ShortcutPlatform.windows),
    ]) {
      test(
        'accepts three and four distinct modifiers in ${runtime.name} on ${platform.name} and still detects conflicts',
        () {
          const c = ShortcutModifier.control;
          const a = ShortcutModifier.alt;
          const s = ShortcutModifier.shift;
          const m = ShortcutModifier.meta;
          for (final mods in [
            [c, a, s],
            [c, a, m],
            [c, s, m],
            [a, s, m],
            [c, a, s, m],
          ]) {
            for (final code in ['KeyN', 'KeyR', 'KeyX', 'Tab', 'F4']) {
              expect(
                bindingIssue(
                  normalizeBinding(ShortcutBinding(code, mods), platform),
                  runtime,
                  platform,
                ),
                isNull,
              );
            }
          }
          const binding = ShortcutBinding('KeyX', [
            ShortcutModifier.primary,
            a,
            s,
          ]);
          var document = const ShortcutDocument.empty();
          for (final entry in definitions) {
            document = editShortcutDocument(
              document,
              SetShortcut(entry.id, binding),
              runtime,
              platform,
            );
          }
          expect(conflicts(definitions, document, runtime, platform), [
            ['test.two'],
            ['test.one'],
          ]);
          expect(
            bindingIssue(
              normalizeBinding(const ShortcutBinding('KeyN'), platform),
              runtime,
              platform,
            ),
            runtime == ShortcutRuntime.desktop
                ? null
                : BindingIssue.modifierRequired,
          );
        },
      );
    }

    test('counts expanded distinct modifiers and keeps Linux reservations', () {
      expect(
        normalizeBinding(
          const ShortcutBinding('KeyX', [
            ShortcutModifier.primary,
            ShortcutModifier.meta,
            ShortcutModifier.shift,
          ]),
          ShortcutPlatform.macos,
        ).modifiers,
        [ShortcutModifier.shift, ShortcutModifier.meta],
      );
      expect(
        bindingIssue(
          normalizeBinding(
            const ShortcutBinding('KeyN', [
              ShortcutModifier.primary,
              ShortcutModifier.control,
              ShortcutModifier.control,
            ]),
            ShortcutPlatform.windows,
          ),
          ShortcutRuntime.web,
          ShortcutPlatform.windows,
        ),
        BindingIssue.unsupportedBrowser,
      );
      expect(
        bindingIssue(
          normalizeBinding(
            const ShortcutBinding('KeyN', [
              ShortcutModifier.control,
              ShortcutModifier.alt,
              ShortcutModifier.shift,
            ]),
            ShortcutPlatform.linux,
          ),
          ShortcutRuntime.web,
          ShortcutPlatform.linux,
        ),
        BindingIssue.unsupportedBrowser,
      );
    });

    test('selects each owner-declared profile without inheriting or rewriting another profile', () {
      final entry = ShortcutDefinition(
        id: 'page.refresh',
        defaults: {
          'desktop:macos': primary('KeyR'),
          'desktop:windows': primary('KeyR'),
          'web:macos': const ShortcutBinding('KeyP', [
            ShortcutModifier.primary,
            ShortcutModifier.shift,
          ]),
          'web:windows': const ShortcutBinding('KeyJ', [
            ShortcutModifier.primary,
            ShortcutModifier.alt,
          ]),
        },
      );
      const document = ShortcutDocument.empty();
      NormalizedBinding? effective(
        ShortcutRuntime r,
        ShortcutPlatform p, [
        ShortcutDocument source = document,
      ]) => effectiveShortcuts([entry], source, r, p)[0].binding;
      expect(
        effective(ShortcutRuntime.desktop, ShortcutPlatform.macos),
        const NormalizedBinding('KeyR', [ShortcutModifier.meta]),
      );
      expect(
        effective(ShortcutRuntime.desktop, ShortcutPlatform.windows),
        const NormalizedBinding('KeyR', [ShortcutModifier.control]),
      );
      expect(
        effective(ShortcutRuntime.web, ShortcutPlatform.macos),
        const NormalizedBinding('KeyP', [
          ShortcutModifier.shift,
          ShortcutModifier.meta,
        ]),
      );
      expect(
        effective(ShortcutRuntime.web, ShortcutPlatform.windows),
        const NormalizedBinding('KeyJ', [
          ShortcutModifier.control,
          ShortcutModifier.alt,
        ]),
      );
      expect(
        effective(ShortcutRuntime.desktop, ShortcutPlatform.linux),
        isNull,
      );
      expect(effective(ShortcutRuntime.web, ShortcutPlatform.linux), isNull);
      final override = editShortcutDocument(
        document,
        const SetShortcut('page.refresh', null),
        ShortcutRuntime.web,
        ShortcutPlatform.macos,
      );
      expect(
        effective(ShortcutRuntime.web, ShortcutPlatform.macos, override),
        isNull,
      );
      final reset = editShortcutDocument(
        override,
        const ResetShortcut('page.refresh'),
        ShortcutRuntime.web,
        ShortcutPlatform.macos,
      );
      expect(
        effective(ShortcutRuntime.web, ShortcutPlatform.macos, reset),
        const NormalizedBinding('KeyP', [
          ShortcutModifier.shift,
          ShortcutModifier.meta,
        ]),
      );
      expect(() => validateDefaults([entry]), returnsNormally);
      expect(
        () => validateDefaults([
          entry,
          ShortcutDefinition(id: 'other.refresh', defaults: entry.defaults),
        ]),
        throwsA(
          isA<ShortcutBindingError>().having(
            (e) => e.message,
            'message',
            contains('Conflicting'),
          ),
        ),
      );
    });

    test(
      'keeps browser admission separate from per-profile default selection',
      () {
        for (final platform in [
          ShortcutPlatform.macos,
          ShortcutPlatform.windows,
        ]) {
          final prim = platform == ShortcutPlatform.macos
              ? ShortcutModifier.meta
              : ShortcutModifier.control;
          for (final other in [ShortcutModifier.alt, ShortcutModifier.shift]) {
            expect(
              bindingIssue(
                normalizeBinding(
                  ShortcutBinding('KeyX', [prim, other]),
                  platform,
                ),
                ShortcutRuntime.web,
                platform,
              ),
              isNull,
            );
          }
        }
        expect(
          bindingIssue(
            normalizeBinding(primary('Backquote'), ShortcutPlatform.macos),
            ShortcutRuntime.web,
            ShortcutPlatform.macos,
          ),
          BindingIssue.unsupportedBrowser,
        );
        expect(
          bindingIssue(
            normalizeBinding(
              const ShortcutBinding('KeyB', [ShortcutModifier.alt]),
              ShortcutPlatform.macos,
            ),
            ShortcutRuntime.web,
            ShortcutPlatform.macos,
          ),
          BindingIssue.reserved,
        );
        expect(
          bindingIssue(
            normalizeBinding(primary('KeyN'), ShortcutPlatform.windows),
            ShortcutRuntime.web,
            ShortcutPlatform.windows,
          ),
          BindingIssue.unsupportedBrowser,
        );
      },
    );

    test('validates edits and active definitions rather than trusting renderer fields', () {
      final parsed = parseShortcutDefinitions([
        {
          'id': 'test.one',
          'defaults': {
            'desktop:macos': primaryJson('KeyB'),
            'desktop:windows': primaryJson('KeyB'),
            'desktop:linux': primaryJson('KeyB'),
          },
        },
      ]);
      expect(parsed.single.id, 'test.one');
      expect(
        (parseShortcutEdit({
          'type': 'set',
          'id': 'test.one',
          'binding': null,
        }) as SetShortcut).binding,
        isNull,
      );
      expect(
        parseShortcutEdit({'type': 'reset', 'id': 'test.one'}),
        isA<ResetShortcut>(),
      );
      expect(
        parseShortcutEdit({'type': 'reset-all'}),
        isA<ResetAllShortcuts>(),
      );
      for (final value in [
        null,
        <String, Object?>{},
        {'type': 'recover'},
        {'type': 'reset', 'id': '../x'},
        {'type': 'reset-all', 'path': '/tmp'},
        {'type': 'other', 'id': 'test.one'},
      ]) {
        expect(
          () => parseShortcutEdit(value),
          throwsA(anything),
          reason: '$value',
        );
      }
      Map<String, Object?> entry(Map<String, Object?> defaults) => {
        'id': 'test.one',
        'defaults': defaults,
      };
      for (final value in <Object?>[
        null,
        [
          entry({
            'desktop:macos': null,
            'desktop:windows': null,
            'desktop:linux': null,
          }),
        ],
        [entry({}), entry({})],
        [
          entry({'other': primaryJson('KeyJ')}),
        ],
        [
          entry({
            'web:macos': primaryJson('KeyN'),
            'web:windows': primaryJson('KeyN'),
            'web:linux': primaryJson('KeyN'),
          }),
        ],
        [
          entry({
            'desktop:macos': primaryJson('KeyC'),
            'desktop:windows': primaryJson('KeyC'),
            'desktop:linux': primaryJson('KeyC'),
          }),
        ],
      ]) {
        expect(
          () => parseShortcutDefinitions(value),
          throwsA(anything),
          reason: '$value',
        );
      }
    });
  });
}
