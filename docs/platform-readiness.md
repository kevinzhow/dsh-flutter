# Platform verification and installation

The Windows native runner is present and uses the Whalee application title, binary and existing whale artwork. This is source preparation, not a Windows build or runtime result. Linux and Android are exercised on k172. macOS and iOS projects are present; their current native builds, device interaction and Apple signing still require the corresponding SDKs and devices. No application is published by these tools.

The next application version is 0.0.2+2. APK upgrade checks require the same application ID and signing certificate and an increased version code. `tool/platform/apk_identity.py` obtains these facts from `apksigner verify` and `aapt dump badging`, without reading private keys. `--require-release --expected-cert-sha256 <fingerprint>` refuses Android Debug certificates and unexpected signing identities. Development release builds may still use the debug key, and must be described as such.

A production signing build must supply an existing `android/key.properties` and its keystore through a private provisioning path. The signing identity is a long-term owner decision because later upgrades must retain it. Gradle property `-PwhaleeRequireReleaseSigning=true` refuses a missing configuration; any present configuration must name all four fields and an existing keystore. Do not commit the configuration or key. No production keystore or repository secrets have been created or changed by this work.

To run the device upgrade fixture, build `test/parity/platform_upgrade_main.dart` twice: first with `--build-name 0.0.1 --build-number 1 --dart-define=UPGRADE_STAGE=before`, then with `--build-name 0.0.2 --build-number 2 --dart-define=UPGRADE_STAGE=after`. Keep the two APKs separately. Build the normal application afterward. On an owned emulator, run:

```sh
python3 tool/platform/android_upgrade.py --sdk /path/to/android-sdk --build-tools /path/to/android-sdk/build-tools/36.0.0 --serial emulator-5560 --before /path/to/before.apk --after /path/to/after.apk --restore /path/to/normal.apk --out build/platform-upgrade
```

This performs actual replacement installs, checks eight synthetic persistent values, then restores and stops the normal APK. It tests SharedPreferences, the production secure connection store, sidebar state and the original task binding. A debug-signed run establishes development upgrade behavior, not a production-signing result. Real devices and store distribution need their own evidence.

Sidebar snapshots are bounded device data scoped to the Host origin and original Session. Their layout references, allocation counter and two-pane graph are validated before rendering; undo history starts fresh. Files, guide pages, plans, review resources and explicitly declared task bindings can restore. Transient documents and navigation parameters are not serialized. A terminal reports its stable Host identity into the durable binding. Restoration reattaches only that existing identity; a missing Host terminal stays missing even on retry. Legacy terminal tabs without a binding are retired. Reopening Whalee never creates a replacement shell implicitly. Corrupt or inaccessible storage does not stop a live sidebar.

Release acceptance still requires real macOS/Windows/iOS builds and interaction, the owner-selected Android signing identity, signed installation/upgrade evidence and the outstanding visual alignment work. CI or Dart compilation alone must not be reported as device validation.
