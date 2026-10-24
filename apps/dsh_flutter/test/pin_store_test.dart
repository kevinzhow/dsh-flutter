import 'package:dsh_flutter/src/local_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pins are kept in the preferences and survive a new store', () async {
    final prefs = MemoryLocalPrefs();
    final store = PrefsPinStore(prefs);
    await store.pin('dsh.example:8443', 'AA:BB');
    await store.pin('10.0.0.5:8443', 'CC:DD');
    expect(PrefsPinStore(prefs).pinFor('dsh.example:8443'), 'AA:BB');
    await store.forget('dsh.example:8443');
    expect(PrefsPinStore(prefs).pinFor('dsh.example:8443'), isNull);
    expect(PrefsPinStore(prefs).pinFor('10.0.0.5:8443'), 'CC:DD');
  });

  test(
    'the platform store round-trips pins and ignores damaged data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedLocalPrefs.load();
      expect(prefs.certificatePins, isEmpty);
      await prefs.setCertificatePins({'a:1': 'X'});
      expect(prefs.certificatePins, {'a:1': 'X'});
      SharedPreferences.setMockInitialValues({
        'whalee.certificatePins': '{oops',
      });
      expect((await SharedLocalPrefs.load()).certificatePins, isEmpty);
      SharedPreferences.setMockInitialValues({
        'whalee.certificatePins': '{"a:1":"X","b:2":5}',
      });
      expect((await SharedLocalPrefs.load()).certificatePins, {'a:1': 'X'});
    },
  );
}
