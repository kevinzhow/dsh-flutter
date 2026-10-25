# Queue controls and busy Enter

Source a09e0fc13a8285cc9dac4265fad16ed7c30b6e02; tree f14539c037094a83b854a0add24eeb41e50c34fd, based on main ce3b6a6. All data is synthetic.

All 12 full preflight checks pass, no check skipped. Normal Linux/Android release and native fixture builds pass. The screenshot matrix contains 80 comparisons with matching dimensions; queue mean non-text similarity96.667%, busy-Enter97.774%. Strict99.5% target passes0/80: visual alignment remains open. Fonts, classifier and thresholds were unchanged. The last editor focus tracking change leaves the captured focused appearance unchanged.

Native Weston14 / Intel LNL GL desktop1280x720 lightEN and phone390x844 darkZH each pass four pointer/keyboard assertions. Captures were manually checked for actual edited text and successful remove/steer actions. AndroidAPI36 darkZH passes18 tap/keyboard scenes covering failed-edit draft preservation, retry, remove, steer, idle disabling and Host-setting-derived prompt delivery. Native actions use an in-memory fixture; actual app service routing is separately covered by queue_flow_test.dart.

All owned app/compositor processes stopped. Normal APK restored and app stopped, owned emulator5560 stopped; shared ADB retained. No deployment or release.
