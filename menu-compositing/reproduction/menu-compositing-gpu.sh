#!/usr/bin/env bash
set -euo pipefail
source [workspace]/scripts/pr16-env.sh
menu_gpu_repo="$WHALEE_AGENT_ROOT/scratch/whalee-menu-compositing"
python3 "$WHALEE_AGENT_ROOT/scripts/menu-compositing-gpu-proof.py" \
  --repo "$menu_gpu_repo" \
  --builds "$menu_gpu_repo/.local/menu-compositing-builds" \
  --manifest "$menu_gpu_repo/tool/parity-desktop/reported-families-cases.json" \
  --out "$menu_gpu_repo/build/native-menu-compositing-gpu" \
  --app-home "$menu_gpu_repo/.local/menu-compositing-native-home" \
  --expected-head 4feb2c38e63fc61f0e2a6dab125bd5709be7ccb2 \
  --expected-tree a32ed26154623c6ee9ced491712348f44330557f \
  "$@"
