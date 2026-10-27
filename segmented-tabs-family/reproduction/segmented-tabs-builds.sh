#!/usr/bin/env bash
set -euo pipefail
source [workspace]/scripts/pr16-env.sh
repo="$WHALEE_AGENT_ROOT/scratch/whalee-segmented-tabs"
cd "$repo/apps/dsh_flutter"
out="$repo/.local/segmented-tabs-builds-final2"
mkdir "$out"
flutter build linux --release --target test/parity/segmented_tabs_main.dart > "$out/linux-fixture.log" 2>&1
cp -a build/linux/x64/release/bundle "$out/linux-fixture"
flutter build apk --debug --target test/parity/segmented_tabs_main.dart > "$out/android-fixture.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$out/android-fixture.apk"
flutter build linux --release > "$out/linux-normal.log" 2>&1
cp -a build/linux/x64/release/bundle "$out/linux-normal"
flutter build apk --debug > "$out/android-normal.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$out/android-normal.apk"
