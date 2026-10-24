import 'package:dsh_client/generated_permission_presets.dart' as perm;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_permission_presets/dsh_feature_permission_presets.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);

void main() {
  const catalog = perm.PermissionCatalog(
    options: [
      perm.PresetOption(
        value: 'read-only',
        name: 'read-only',
        description: 'Read files.',
      ),
      perm.PresetOption(value: 'workspace-write', name: 'workspace-write'),
      perm.PresetOption(value: 'auto', name: 'auto'),
      perm.PresetOption(
        value: 'danger-full-access',
        name: 'danger-full-access',
      ),
    ],
    defaultOptions: [],
    defaultPreset: 'workspace-write',
  );

  test('the rows mark the session value and gate full access and Auto review behind their own risk copy', () {
    final rows = permissionOptions(catalog, 'workspace-write', en);
    expect(rows.map((r) => r.label), [
      'Read Only',
      'Workspace Write',
      'Auto review',
      'Full access',
    ]);
    expect(rows.where((r) => r.active).map((r) => r.id), ['workspace-write']);
    expect(rows[2].badge, isNotNull);
    expect(rows[2].confirmation!.title, isNot(rows[3].confirmation!.title));
    expect(rows[0].confirmation, isNull);
    expect(rows[1].confirmation, isNull);
  });

  test(
    'the popup decorates the host command and needs the session value',
    () async {
      final registry = CommandUiRegistry();
      final host = FakeHost()
        ..handlers['permissionPresets/catalog'] = (_) => catalog.toJson();
      host.generation = FakeGeneration();
      final store = ProjectionStore()
        ..apply('permissions', {'currentValue': 'read-only'}, 1);
      final submitted = <String>[];
      final directory = PermissionCatalogDirectory(host.remotes);
      addTearDown(directory.dispose);
      decoratePermissionCommand(
        registry,
        catalog: directory,
        projectionsOf: (id) => id == 's1' ? store : null,
        submit: (id, preset) async => submitted.add('$id $preset'),
        i18n: () => en,
      );
      final d = registry.decorations['permission']!;
      expect(d.available('s1'), isTrue);
      expect(d.available('s2'), isFalse);
      final spec = d.ui as PopupSelectSpec;
      final rows = await spec.options('s1', AbortSignal.never);
      expect(rows.where((r) => r.active).single.id, 'read-only');
      await spec.onSelect(rows[1], 's1');
      expect(submitted, ['s1 workspace-write']);
      await expectLater(
        spec.options('s2', AbortSignal.never),
        throwsStateError,
      );
    },
  );
}
