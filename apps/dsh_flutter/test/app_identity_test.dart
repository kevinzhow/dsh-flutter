import 'dart:io';

import 'package:dsh_flutter/src/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// The product name and id live in app_identity.dart; the platform manifests
/// repeat them and must not drift.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Android carries the name and the application id', () {
    expect(
      read('android/app/src/main/AndroidManifest.xml'),
      contains('android:label="$appDisplayName"'),
    );
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle, contains('namespace = "$appId"'));
    expect(gradle, contains('applicationId = "$appId"'));
    expect(
      File(
        'android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt',
      ).existsSync(),
      isTrue,
    );
    expect(
      read(
        'android/app/src/main/kotlin/${appId.replaceAll('.', '/')}/MainActivity.kt',
      ),
      contains('package $appId'),
    );
  });

  test('iOS carries the name and the bundle id', () {
    expect(
      read('ios/Runner/Info.plist'),
      contains('<string>$appDisplayName</string>'),
    );
    final project = read('ios/Runner.xcodeproj/project.pbxproj');
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = $appId;'));
    expect(project, isNot(contains('dshFlutter')));
  });

  test('Linux carries the name and the application id', () {
    expect(
      read('linux/CMakeLists.txt'),
      contains('set(APPLICATION_ID "$appId")'),
    );
    expect(
      read('linux/runner/my_application.cc'),
      contains('"$appDisplayName"'),
    );
  });

  test('no official DeepSeek logo or brand asset ships with the app', () {
    final assets = Directory('.')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.toLowerCase())
        .where((p) => !p.contains('/build/') && !p.contains('.dart_tool'))
        .where(
          (p) =>
              p.contains('deepseek') &&
              (p.endsWith('.png') || p.endsWith('.svg')),
        );
    expect(assets, isEmpty);
  });
}
