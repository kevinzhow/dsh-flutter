#!/usr/bin/env bash
set -euo pipefail

# Build helper with functions, quoting and expansions.
ROOT="${ROOT:-$(pwd)}"
declare -a targets=(alpha beta "gamma delta")

usage() {
  echo "usage: $0 [-v] <target>" >&2
  exit 2
}

log() { printf '%s [%s] %s\n' "$(date +%H:%M)" "$1" "${*:2}"; }

while getopts "v" opt; do
  case $opt in
    v) VERBOSE=1 ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

for t in "${targets[@]}"; do
  if [[ -n "${VERBOSE:-}" && $t == a* ]]; then
    log info "building $t"
  elif [ -d "$ROOT/$t" ]; then
    (cd "$ROOT/$t" && make -j"$(nproc)" 2>&1 | tee build.log)
  fi
done

cat <<'DOC' > notes.txt
literal $HOME is not expanded
DOC
cat <<EOT
expanded $ROOT and $(echo nested)
EOT
echo 'single \n quoted' "double \"escaped\" \$x" `uname -s`
