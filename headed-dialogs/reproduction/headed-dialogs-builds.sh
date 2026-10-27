#!/usr/bin/env bash
set -euo pipefail
source [workspace]/scripts/pr16-env.sh
repo="$WHALEE_AGENT_ROOT/scratch/whalee-headed-dialogs"
cd "$repo/apps/dsh_flutter"
out="$repo/.local/headed-dialogs-builds"
mkdir "$out"
git -C "$repo" diff --quiet
git -C "$repo" diff --cached --quiet
git -C "$repo" rev-parse HEAD > "$out/runtime-head.txt"
git -C "$repo" rev-parse 'HEAD^{tree}' > "$out/runtime-tree.txt"
flutter build linux --release --target test/parity/headed_dialogs_main.dart > "$out/linux-fixture.log" 2>&1
cp -a build/linux/x64/release/bundle "$out/linux-fixture"
touch "$out/linux-fixture.ready"
flutter build apk --debug --target test/parity/headed_dialogs_main.dart > "$out/android-fixture.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$out/android-fixture.apk"
touch "$out/android-fixture.ready"
flutter build linux --release > "$out/linux-normal.log" 2>&1
cp -a build/linux/x64/release/bundle "$out/linux-normal"
flutter build apk --debug > "$out/android-normal.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$out/android-normal.apk"
