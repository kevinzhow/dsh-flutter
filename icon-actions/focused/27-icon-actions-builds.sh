#!/usr/bin/env bash
set -euo pipefail
source [workspace]/scripts/pr16-env.sh
icon_build_repo="$WHALEE_AGENT_ROOT/scratch/whalee-icon-actions"
icon_build_out="${1:-$icon_build_repo/.local/icon-actions-builds}"
cd "$icon_build_repo"
test -z "$(git status --porcelain)"
mkdir "$icon_build_out"
git rev-parse HEAD > "$icon_build_out/runtime-head.txt"
git rev-parse 'HEAD^{tree}' > "$icon_build_out/runtime-tree.txt"
cd apps/dsh_flutter
nice -n 15 flutter build linux --release --target test/parity/icon_actions_main.dart > "$icon_build_out/linux-fixture.log" 2>&1
cp -a build/linux/x64/release/bundle "$icon_build_out/linux-fixture"
touch "$icon_build_out/linux-fixture.ready"
nice -n 15 flutter build apk --debug --target test/parity/icon_actions_main.dart > "$icon_build_out/android-fixture.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$icon_build_out/android-fixture.apk"
touch "$icon_build_out/android-fixture.ready"
nice -n 15 flutter build linux --release > "$icon_build_out/linux-normal.log" 2>&1
cp -a build/linux/x64/release/bundle "$icon_build_out/linux-normal"
nice -n 15 flutter build apk --debug > "$icon_build_out/android-normal.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$icon_build_out/android-normal.apk"
touch "$icon_build_out/normal.ready"
