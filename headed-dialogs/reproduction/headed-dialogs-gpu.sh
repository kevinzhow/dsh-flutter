#!/usr/bin/env bash
set -euo pipefail
source [workspace]/scripts/pr16-env.sh
repo="$WHALEE_AGENT_ROOT/scratch/whalee-headed-dialogs"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export PARITY_DESKTOP_APP="$repo/.local/headed-dialogs-builds/linux-fixture/dsh_flutter"
export PARITY_DESKTOP_HOME="$repo/.local/native-headed-home-final-scroll"
unset PARITY_DESKTOP_HOST_LOG
python "$repo/tool/parity-desktop/gpu_capture.py" "$repo/build/native-headed-gpu" "$repo/tool/parity-desktop/headed-dialogs-cases.json"
