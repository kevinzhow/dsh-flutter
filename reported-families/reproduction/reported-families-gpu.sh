#!/usr/bin/env bash
set -euo pipefail
source [workspace]/scripts/pr16-env.sh
repo="$WHALEE_AGENT_ROOT/scratch/whalee-reported-families"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export PARITY_DESKTOP_APP="$repo/.local/reported-builds/linux-fixture/dsh_flutter"
export PARITY_DESKTOP_HOME="${REPORTED_GPU_HOME:-$repo/.local/reported-native-home}"
reported_gpu_out="${REPORTED_GPU_OUT:-$repo/build/native-reported-gpu}"
test -f "$repo/.local/reported-builds/linux-fixture.ready" || { echo "The reported-family fixture is not ready" >&2; exit 1; }
unset PARITY_DESKTOP_HOST_LOG
python "$repo/tool/parity-desktop/gpu_capture.py" "$reported_gpu_out" "$repo/tool/parity-desktop/reported-families-cases.json" "$@"
