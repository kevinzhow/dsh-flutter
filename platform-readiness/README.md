# Sidebar persistence and platform upgrade verification

Final source `c6de0886c8bd1d14069a1c6a55fdc805a0f94fe5`; runtime `6788fc3b4ca86268a81cd054e1daa0d64fa87cde`. Later changes only correct the native replay manifest, including its keyboard operation and Connect coordinates. All content is synthetic.

- Full local preflight on the runtime: all12 checks passed without skipped checks. The final source also passed all11 fast checks. Actual pinned TypeScript layout-validation decisions match Dart; graph corruption, identity allocation, Host/Session isolation, original task binding and ordered/bounded storage have regressions.
- Root application recreation preserves the original task binding and isolates another Host using the same Session id. Disposal stops list events before asynchronous teardown.
- A real isolated DSH Host created one synthetic terminal, restored that exact identity, and retried a missing identity twice without creating replacement work. No model invoked; the owned Host and its process were stopped.
- AndroidAPI36 actual replacement installs from0.0.1+1 to0.0.2+2 preserve all8 synthetic settings/secure-store/sidebar/task checks. Both APKs use the same Debug signer. This is development upgrade evidence; production signing is **not validated**.
- The actual Gradle requirement refuses absent production signing configuration. The APK identity checker refuses to label a real Android Debug certificate as production signing.
- Final Linux normal and Android before/after/normal release-mode builds passed; hashes are in the receipt. Release-mode compilation is separate from production signing.
- Weston14 / Intel LNL: desktop light English and phone dark Chinese each pass3 actual input assertions: keyboard input, rejected invalid pairing and opening Settings. Error screenshots were manually inspected. No visual-parity claim is made.
- Windows native runner, app metadata and existing Whalee artwork are prepared; Windows build/runtime, macOS/iOS device tests and the owner-selected production Android key remain **pending**. No repository secret, production key, deployment or release was created.

[Android upgrade](android/after.png) · [Android receipt](android/receipt.json) · [Desktop error](gpu/platform.desktop/invalid-link.png) · [Phone error](gpu/platform.phone/invalid-link.png) · [Real terminal receipt](terminal-live/receipt.json) · [Complete receipt](receipt.json)

Normal Android APK restored and stopped; owned emulator, Weston and application runtimes stopped. Shared ADB retained.
