#!/usr/bin/env bash
set -euo pipefail
source [workspace]/scripts/pr16-env.sh
header_build_repo="$WHALEE_AGENT_ROOT/scratch/whalee-source-shadows"
header_build_out="${1:-$header_build_repo/.local/header-shadows-builds}"
cd "$header_build_repo"
test -z "$(git status --porcelain)"
mkdir "$header_build_out"
git rev-parse HEAD > "$header_build_out/runtime-head.txt"
git rev-parse 'HEAD^{tree}' > "$header_build_out/runtime-tree.txt"
cd apps/dsh_flutter
nice -n 15 flutter build linux --release --target test/parity/reported_families_main.dart > "$header_build_out/linux-fixture.log" 2>&1
cp -a build/linux/x64/release/bundle "$header_build_out/linux-fixture"
touch "$header_build_out/linux-fixture.ready"
nice -n 15 flutter build apk --debug --target test/parity/reported_families_main.dart > "$header_build_out/android-fixture.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$header_build_out/android-fixture.apk"
touch "$header_build_out/android-fixture.ready"
nice -n 15 flutter build linux --release > "$header_build_out/linux-normal.log" 2>&1
cp -a build/linux/x64/release/bundle "$header_build_out/linux-normal"
nice -n 15 flutter build apk --debug > "$header_build_out/android-normal.log" 2>&1
cp build/app/outputs/flutter-apk/app-debug.apk "$header_build_out/android-normal.apk"
touch "$header_build_out/normal.ready"
