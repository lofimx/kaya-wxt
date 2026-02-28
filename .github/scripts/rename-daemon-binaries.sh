#!/usr/bin/env bash
# Renames daemon binaries to include the Rust target triple,
# e.g. savebutton-daemon -> savebutton-daemon-aarch64-apple-darwin
#
# Usage: bin/rename-daemon-binaries.sh <artifacts-dir>
#   artifacts-dir should contain subdirectories named daemon-<target-triple>/

set -euo pipefail

artifacts_dir="${1:?Usage: $0 <artifacts-dir>}"

for dir in "$artifacts_dir"/daemon-*; do
  [ -d "$dir" ] || continue
  target="${dir#"$artifacts_dir"/daemon-}"
  for file in "$dir"/*; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    if [[ "$name" == *.* ]]; then
      ext=".${name##*.}"
      base="${name%.*}"
    else
      ext=""
      base="$name"
    fi
    mv "$file" "$dir/${base}-${target}${ext}"
  done
done
