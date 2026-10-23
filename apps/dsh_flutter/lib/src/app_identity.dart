/// The product identity, defined once. The platform manifests carry the same
/// strings (Android `app/build.gradle`, `AndroidManifest.xml`, iOS
/// `Info.plist`, macOS `AppInfo.xcconfig`, Linux `CMakeLists.txt`);
/// `test/app_identity_test.dart` fails when a manifest drifts from these.
///
/// The working name "Whalee" was chosen by Kevin on 2026-10-23; the id is
/// `app.kevinzhow.whalee`. Changing the product name means changing
/// [appDisplayName], [appId] and the manifests listed above, nothing else.
library;

/// Name shown on the launcher and in the window title.
const String appDisplayName = 'Whalee';

/// Android applicationId, iOS and macOS bundle identifier.
const String appId = 'app.kevinzhow.whalee';
