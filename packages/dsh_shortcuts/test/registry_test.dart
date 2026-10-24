// The command registry and dispatch rules (dsh `registry.client.spec.ts`,
// `desktop-chords.client.spec.ts`) plus the service on top of it.
import 'package:dsh_shortcuts/dsh_shortcuts.dart';
import 'package:test/test.dart';

import 'support.dart';

const context = ShortcutContext(region: ShortcutRegion.page);

ShortcutGesture gesture({
  String code = 'KeyB',
  bool control = false,
  bool alt = false,
  bool shift = false,
  bool meta = true,
  bool repeat = false,
  bool composing = false,
  bool defaultPrevented = false,
  String? secondCode,
}) => ShortcutGesture(
  code: code,
  secondCode: secondCode,
  control: control,
  alt: alt,
  shift: shift,
  meta: meta,
  repeat: repeat,
  composing: composing,
  defaultPrevented: defaultPrevented,
);

Map<String, ShortcutBinding> allDesktop(ShortcutBinding b) => {
  'desktop:macos': b,
  'desktop:windows': b,
  'desktop:linux': b,
};

ShortcutCommand command({
  String id = 'test.toggle',
  String Function()? label,
  Map<String, ShortcutBinding>? defaults,
  List<ShortcutRegion> regions = const [
    ShortcutRegion.page,
    ShortcutRegion.editable,
  ],
  ShortcutResolution Function(ShortcutContext)? resolve,
}) => ShortcutCommand(
  id: id,
  label: label ?? () => 'Toggle',
  aliases: const ['toggle'],
  defaults: defaults ?? allDesktop(primary('KeyB')),
  regions: regions,
  resolve: resolve ?? (_) => ShortcutHandled(() {}),
);

void main() {
  for (final platform in [ShortcutPlatform.macos, ShortcutPlatform.windows]) {
    test(
      'admits the existing single-modifier Web keys on ${platform.name}',
      () {
        final prim = platform == ShortcutPlatform.macos
            ? ShortcutModifier.meta
            : ShortcutModifier.control;
        for (final code in ['Comma', 'Backslash']) {
          expect(
            isWebBindingAllowed(NormalizedBinding(code, [prim]), platform),
            isTrue,
          );
          expect(
            isWebBindingAllowed(
              NormalizedBinding(code, const [ShortcutModifier.alt]),
              platform,
            ),
            isFalse,
          );
        }
        expect(
          isWebBindingAllowed(
            const NormalizedBinding('Backquote', [ShortcutModifier.control]),
            platform,
          ),
          isTrue,
        );
      },
    );
  }

  test('admits modified Web combinations and refuses two-key chords', () {
    expect(
      isWebBindingAllowed(
        const NormalizedBinding('KeyB', [
          ShortcutModifier.control,
          ShortcutModifier.alt,
          ShortcutModifier.shift,
        ]),
        ShortcutPlatform.windows,
      ),
      isTrue,
    );
    expect(
      isWebBindingAllowed(
        const NormalizedBinding('KeyB', [], 'KeyJ'),
        ShortcutPlatform.macos,
      ),
      isFalse,
    );
  });

  test('leaves Linux terminal control-W and control-R with the terminal while dispatching other bindings', () {
    for (final (code, mods, expected) in [
      ('KeyW', [ShortcutModifier.control], 'pass'),
      ('KeyR', [ShortcutModifier.control], 'pass'),
      ('KeyB', [ShortcutModifier.control], 'handled'),
      ('KeyB', [ShortcutModifier.alt], 'handled'),
      ('KeyB', [ShortcutModifier.control, ShortcutModifier.alt], 'handled'),
      ('KeyB', [ShortcutModifier.control, ShortcutModifier.shift], 'handled'),
    ]) {
      final registry = ShortcutRegistry(
        ShortcutRuntime.desktop,
        ShortcutPlatform.linux,
      );
      var runs = 0;
      var consumed = 0;
      registry.register(
        command(
          defaults: {'desktop:linux': ShortcutBinding(code, mods)},
          regions: const [ShortcutRegion.terminal],
          resolve: (_) => ShortcutHandled(() => runs++),
        ),
      );
      final result = registry.dispatch(
        gesture(
          code: code,
          control: mods.contains(ShortcutModifier.control),
          meta: false,
          alt: mods.contains(ShortcutModifier.alt),
          shift: mods.contains(ShortcutModifier.shift),
        ),
        const ShortcutContext(region: ShortcutRegion.terminal),
        () => consumed++,
      );
      expect(
        result is DispatchHandled ? 'handled' : 'pass',
        expected,
        reason: '$code $mods',
      );
      expect(runs, expected == 'handled' ? 1 : 0);
      expect(consumed, expected == 'handled' ? 1 : 0);
    }
  });

  test(
    'dispatches a Windows Web terminal binding with Control, Meta, and Shift',
    () {
      final registry = ShortcutRegistry(
        ShortcutRuntime.web,
        ShortcutPlatform.windows,
      );
      var runs = 0;
      var consumed = 0;
      registry.register(
        command(
          defaults: {
            'web:windows': const ShortcutBinding('KeyB', [
              ShortcutModifier.control,
              ShortcutModifier.meta,
              ShortcutModifier.shift,
            ]),
          },
          regions: const [ShortcutRegion.terminal],
          resolve: (_) => ShortcutHandled(() => runs++),
        ),
      );
      final r = registry.dispatch(
        gesture(control: true, shift: true),
        const ShortcutContext(region: ShortcutRegion.terminal),
        () => consumed++,
      );
      expect(r, isA<DispatchHandled>());
      expect((runs, consumed), (1, 1));
    },
  );

  for (final status in ['pass', 'blocked']) {
    test('does not execute a menu command whose owner returns $status', () {
      final registry = ShortcutRegistry(
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      );
      ShortcutContext? seen;
      registry.register(
        command(
          resolve: (c) {
            seen = c;
            return status == 'pass'
                ? const ShortcutPass()
                : const ShortcutBlocked('unavailable');
          },
        ),
      );
      registry.invoke('test.toggle', context);
      expect(seen?.source, ShortcutSource.menu);
    });
  }

  group('physical key registry', () {
    test('normalizes primary/control together on Windows and presents platform-specific keys', () {
      const b = ShortcutBinding('KeyB', [
        ShortcutModifier.primary,
        ShortcutModifier.control,
        ShortcutModifier.shift,
      ]);
      expect(
        bindingKey(normalizeBinding(b, ShortcutPlatform.windows)),
        'control+shift+KeyB',
      );
      expect(
        presentBinding(
          normalizeBinding(b, ShortcutPlatform.macos),
          ShortcutPlatform.macos,
        ),
        const PresentedBinding(['⌃', '⇧', '⌘', 'B'], 'Control+Shift+Meta+B'),
      );
      expect(
        presentBinding(
          normalizeBinding(
            const ShortcutBinding('Slash', [ShortcutModifier.primary]),
            ShortcutPlatform.windows,
          ),
          ShortcutPlatform.windows,
        ),
        const PresentedBinding(['Ctrl', '+', '/'], 'Control+/'),
      );
      expect(
        presentBinding(null, ShortcutPlatform.linux),
        const PresentedBinding([], null),
      );
      expect(
        () => normalizeBinding(
          const ShortcutBinding('Unidentified'),
          ShortcutPlatform.macos,
        ),
        throwsA(
          isA<ShortcutBindingError>().having(
            (e) => e.message,
            'message',
            contains('Unsupported'),
          ),
        ),
      );
    });

    test('rejects duplicate ids, cross-platform default conflicts, and unverified Web combinations atomically', () {
      final registry = ShortcutRegistry(
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      );
      final off = registry.register(command());
      expect(
        () => registry.register(command()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'm',
            contains('Duplicate'),
          ),
        ),
      );
      expect(
        () => registry.register(
          command(
            id: 'other.toggle',
            defaults: allDesktop(
              const ShortcutBinding('KeyB', [ShortcutModifier.control]),
            ),
          ),
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'm', contains('windows')),
        ),
      );
      expect(
        () => registry.register(
          command(
            id: 'web.new',
            defaults: {
              for (final p in ['web:macos', 'web:windows', 'web:linux'])
                p: primary('KeyN'),
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'm',
            contains('Unsupported Web'),
          ),
        ),
      );
      expect(
        () => registry.register(
          command(id: 'system.copy', defaults: allDesktop(primary('KeyC'))),
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'm', contains('Reserved')),
        ),
      );
      expect(registry.catalog, hasLength(1));
      var changed = 0;
      registry.subscribe(() => changed++);
      off();
      off();
      expect(changed, 1);
      expect(registry.catalog, isEmpty);
      expect(registry.dispatch(gesture(), context, () {}), isA<DispatchPass>());
    });

    test('consumes before executing, ignores repeats, and matches every modifier exactly', () {
      final registry = ShortcutRegistry(
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      );
      var consumed = 0;
      var runs = 0;
      registry.register(
        command(
          resolve: (_) => ShortcutHandled(() {
            expect(consumed, greaterThan(0));
            runs++;
          }),
        ),
      );
      expect(
        registry.dispatch(gesture(), context, () => consumed++),
        isA<DispatchHandled>(),
      );
      expect(
        registry.dispatch(gesture(repeat: true), context, () => consumed++),
        isA<DispatchHandled>(),
      );
      expect(runs, 1);
      expect(consumed, 2);
      for (final g in [
        gesture(shift: true),
        gesture(alt: true),
        gesture(control: true),
        gesture(meta: false),
        gesture(composing: true),
        gesture(defaultPrevented: true),
      ]) {
        expect(
          registry.dispatch(g, context, () => consumed++),
          isA<DispatchPass>(),
        );
      }
      expect(consumed, 2);
    });

    test('prioritizes desktop bindings in terminals and modals while retaining owner refusal reasons', () {
      final registry = ShortcutRegistry(
        ShortcutRuntime.desktop,
        ShortcutPlatform.macos,
      );
      var consumed = 0;
      var calls = 0;
      ShortcutResolution next = const ShortcutBlocked('No target');
      registry.register(
        command(
          resolve: (_) {
            calls++;
            return next;
          },
        ),
      );
      final blocked = registry.dispatch(
        gesture(),
        const ShortcutContext(region: ShortcutRegion.page, modal: 'settings'),
        () => consumed++,
      );
      expect((blocked as DispatchBlocked).reason, 'No target');
      expect(calls, 1);
      expect(
        registry.dispatch(
          gesture(),
          const ShortcutContext(region: ShortcutRegion.terminal),
          () => consumed++,
        ),
        isA<DispatchBlocked>(),
      );
      expect(
        (registry.dispatch(
          gesture(),
          context,
          () => consumed++,
        ) as DispatchBlocked).reason,
        'No target',
      );
      next = const ShortcutPass();
      expect(
        registry.dispatch(gesture(), context, () => consumed++),
        isA<DispatchPass>(),
      );
      expect(consumed, 3);
    });

    test(
      'publishes stable effective rows with Windows Web three-key defaults',
      () {
        final registry = ShortcutRegistry(
          ShortcutRuntime.web,
          ShortcutPlatform.windows,
        );
        var label = 'Settings';
        registry.register(
          command(
            label: () => label,
            defaults: {
              'web:windows': const ShortcutBinding('KeyB', [
                ShortcutModifier.primary,
                ShortcutModifier.alt,
              ]),
            },
          ),
        );
        final first = registry.catalog;
        expect(identical(registry.catalog, first), isTrue);
        expect(first[0].keys, ['Ctrl', '+', 'Alt', '+', 'B']);
        label = '设置';
        registry.refreshLabels();
        expect(registry.catalog[0].label, '设置');
        expect(
          registry.dispatch(
            gesture(control: true, meta: false),
            context,
            () {},
          ),
          isA<DispatchPass>(),
        );
      },
    );
  });

  for (final code in ['Space', 'Escape', 'ArrowUp']) {
    test('uses standard ARIA names for $code', () {
      expect(
        presentBinding(
          normalizeBinding(ShortcutBinding(code), ShortcutPlatform.windows),
          ShortcutPlatform.windows,
        ).aria,
        code,
      );
    });
  }

  test('keeps commands disabled during startup and publishes config/catalog together before dispatch changes', () {
    final config = initialShortcutConfig();
    final registry = ShortcutRegistry(
      ShortcutRuntime.desktop,
      ShortcutPlatform.macos,
      config,
    );
    var runs = 0;
    registry.register(command(resolve: (_) => ShortcutHandled(() => runs++)));
    expect(registry.dispatch(gesture(), context, () {}), isA<DispatchPass>());
    final snapshot = config.copyWith(
      status: ShortcutConfigStatus.ready,
      document: ShortcutDocument(
        schemaVersion: 1,
        profiles: {
          'desktop:macos': {'test.toggle': primary('KeyJ')},
        },
      ),
    );
    registry.subscribe(() {
      expect(identical(registry.config, snapshot), isTrue);
      expect(registry.catalog[0].keys, ['⌘', 'J']);
    });
    registry.configure(snapshot);
    expect(registry.dispatch(gesture(), context, () {}), isA<DispatchPass>());
    expect(
      registry.dispatch(gesture(code: 'KeyJ'), context, () {}),
      isA<DispatchHandled>(),
    );
    expect(runs, 1);
  });

  test('blocks conflicting dormant overrides when their plugins return, then releases every row on unload', () {
    final registry = ShortcutRegistry(
      ShortcutRuntime.desktop,
      ShortcutPlatform.macos,
    );
    registry.configure(
      initialShortcutConfig().copyWith(
        status: ShortcutConfigStatus.ready,
        document: ShortcutDocument(
          schemaVersion: 1,
          profiles: {
            'desktop:macos': {
              'test.toggle': primary('KeyJ'),
              'other.toggle': primary('KeyJ'),
            },
          },
        ),
      ),
    );
    var runs = 0;
    final off = registry.register(
      command(resolve: (_) => ShortcutHandled(() => runs++)),
    );
    expect(
      registry.dispatch(gesture(code: 'KeyJ'), context, () {}),
      isA<DispatchHandled>(),
    );
    final other = registry.register(
      command(
        id: 'other.toggle',
        defaults: const {},
        resolve: (_) => ShortcutHandled(() => runs++),
      ),
    );
    var consumed = 0;
    expect(
      registry.dispatch(gesture(code: 'KeyJ'), context, () => consumed++),
      isA<DispatchBlocked>(),
    );
    expect(consumed, 1);
    expect(runs, 1);
    other();
    off();
    expect(registry.catalog, isEmpty);
    expect(
      registry.dispatch(gesture(code: 'KeyJ'), context, () {}),
      isA<DispatchPass>(),
    );
  });

  for (final platform in [ShortcutPlatform.macos, ShortcutPlatform.windows]) {
    test(
      'keeps ${platform.name} priority identical before saving, after saving the same default, and after resetting',
      () {
        final registry = ShortcutRegistry(ShortcutRuntime.desktop, platform);
        var runs = 0;
        registry.register(
          command(
            regions: const [ShortcutRegion.page],
            resolve: (_) => ShortcutHandled(() => runs++),
          ),
        );
        for (final (index, modified) in [false, true, false].indexed) {
          registry.configure(
            registry.config.copyWith(
              revision: 'revision-$index',
              document: ShortcutDocument(
                schemaVersion: 2,
                profiles: modified
                    ? {
                        'desktop:${platform.name}': {
                          'test.toggle': primary('KeyB'),
                        },
                      }
                    : {},
              ),
            ),
          );
          expect(registry.catalog[0].modified, modified);
          final input = gesture(
            meta: platform == ShortcutPlatform.macos,
            control: platform == ShortcutPlatform.windows,
          );
          for (final region in ShortcutRegion.values) {
            for (final modal in [null, 'settings']) {
              expect(
                registry.dispatch(
                  input,
                  ShortcutContext(region: region, modal: modal),
                  () {},
                ),
                isA<DispatchHandled>(),
              );
            }
          }
        }
        expect(runs, 18);
      },
    );
  }

  group('desktop chords', () {
    test('matches a two-key chord in either press order and ignores a single key of it', () {
      final registry = ShortcutRegistry(
        ShortcutRuntime.desktop,
        ShortcutPlatform.windows,
      );
      registry.configure(
        initialShortcutConfig().copyWith(
          status: ShortcutConfigStatus.ready,
          document: ShortcutDocument(
            schemaVersion: 2,
            profiles: {
              'desktop:windows': {
                'test.toggle': const ShortcutBinding('KeyA', [], 'KeyB'),
              },
            },
          ),
        ),
      );
      var runs = 0;
      registry.register(
        command(
          defaults: const {},
          resolve: (_) => ShortcutHandled(() => runs++),
        ),
      );
      expect(
        registry.dispatch(
          gesture(meta: false, code: 'KeyA', secondCode: 'KeyB'),
          context,
          () {},
        ),
        isA<DispatchHandled>(),
      );
      expect(
        registry.dispatch(
          gesture(meta: false, code: 'KeyB', secondCode: 'KeyA'),
          context,
          () {},
        ),
        isA<DispatchHandled>(),
      );
      expect(
        registry.dispatch(gesture(meta: false, code: 'KeyA'), context, () {}),
        isA<DispatchPass>(),
      );
      expect(runs, 2);
    });
  });

  group('ShortcutService', () {
    test('starts from the stored document, enables commands, saves an edit and keeps catalog and config together', () async {
      final storage = MemoryStorage();
      final service = ShortcutService(
        runtime: ShortcutRuntime.desktop,
        platform: ShortcutPlatform.linux,
        storage: storage,
      );
      var runs = 0;
      service.register(
        command(
          defaults: {'desktop:linux': primary('KeyB')},
          resolve: (_) => ShortcutHandled(() => runs++),
        ),
      );
      expect(service.config.status, ShortcutConfigStatus.loading);
      expect(
        service.dispatch(gesture(control: true, meta: false), context, () {}),
        isA<DispatchPass>(),
      );
      await service.start();
      expect(service.config.status, ShortcutConfigStatus.ready);
      expect(service.catalog.single.keys, ['Ctrl', 'B']);
      expect(
        service.dispatch(gesture(control: true, meta: false), context, () {}),
        isA<DispatchHandled>(),
      );
      final saved = await service.edit(
        const SetShortcut(
          'test.toggle',
          ShortcutBinding('KeyJ', [ShortcutModifier.primary]),
        ),
        service.config.revision,
      );
      expect(saved.status, ShortcutSaveStatus.saved);
      expect(service.catalog.single.modified, isTrue);
      expect(service.catalog.single.keys, ['Ctrl', 'J']);
      expect(
        service.dispatch(gesture(control: true, meta: false), context, () {}),
        isA<DispatchPass>(),
      );
      expect(
        service.dispatch(
          gesture(control: true, meta: false, code: 'KeyJ'),
          context,
          () {},
        ),
        isA<DispatchHandled>(),
      );
      expect(runs, 2);
      expect(storage.writes, 1);
      service.dispose();
    });

    test('describes registered binding conflicts', () async {
      final service = ShortcutService(
        runtime: ShortcutRuntime.desktop,
        platform: ShortcutPlatform.linux,
        storage: MemoryStorage(),
      );
      final off = service.register(
        command(defaults: {'desktop:linux': primary('KeyB')}),
      );
      await service.start();
      const candidate = ShortcutBinding('KeyB', [ShortcutModifier.control]);
      expect(service.describeBinding(candidate).conflicts, ['test.toggle']);
      off();
      expect(service.describeBinding(candidate).conflicts, isEmpty);
      expect(service.describeBinding(null).binding, isNull);
      service.dispose();
    });

    test('fails the read visibly when the store cannot be read, and accepts no edit', () async {
      final storage = MemoryStorage()..failReads = true;
      final service = ShortcutService(
        runtime: ShortcutRuntime.desktop,
        platform: ShortcutPlatform.linux,
        storage: storage,
      );
      service.register(command(defaults: {'desktop:linux': primary('KeyB')}));
      await service.start();
      expect(service.config.status, ShortcutConfigStatus.unreadable);
      expect(service.config.error, ShortcutReadError.read);
      final result = await service.edit(
        const ResetAllShortcuts(),
        service.config.revision,
      );
      expect(result.status, ShortcutSaveStatus.unreadable);
      service.dispose();
    });
  });

  group('ModalStack', () {
    test(
      'tracks the top modal and removes exactly the layer a disposer opened',
      () {
        final stack = ModalStack();
        expect(stack.top, isNull);
        final off = stack.push('settings');
        final inner = stack.push('shortcuts');
        expect(stack.top, 'shortcuts');
        off();
        expect(stack.top, 'shortcuts');
        inner();
        inner();
        expect(stack.top, isNull);
      },
    );
  });
}
