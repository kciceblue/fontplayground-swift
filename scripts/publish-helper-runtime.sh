#!/bin/bash
# WP-203: switch a verified runtime and its manifest into place as one recoverable transaction, so a failed or
# interrupted publish never leaves a new runtime next to the previous fpengine-runtime.json (or the reverse).
#
#   publish-helper-runtime.sh <out-dir> <staged-runtime-dir> <staged-manifest>
#   publish-helper-runtime.sh --recover <out-dir>
#
# <out-dir>/.publish-journal exists only while the pair is being switched. It records whether a previous runtime
# and manifest existed; if it is still there, the publish did not finish and the previous pair is restored.
set -euo pipefail

usage() {
  echo 'usage: publish-helper-runtime.sh <out-dir> <runtime-dir> <manifest> | --recover <out-dir>' >&2
  exit 2
}

recover() {
  local out=$1
  local journal="$out/.publish-journal" had_runtime had_manifest
  if [[ -f "$journal" ]]; then
    read -r had_runtime had_manifest <"$journal"
    # Whatever is in place may be half of the new pair: put the previous pair back.
    if [[ -e "$out/.fpengine.old" ]]; then
      rm -rf "$out/fpengine"
      mv "$out/.fpengine.old" "$out/fpengine"
    elif [[ $had_runtime == 0 ]]; then
      rm -rf "$out/fpengine"
    fi
    if [[ -e "$out/.fpengine-runtime.json.old" ]]; then
      rm -f "$out/fpengine-runtime.json"
      mv "$out/.fpengine-runtime.json.old" "$out/fpengine-runtime.json"
    elif [[ $had_manifest == 0 ]]; then
      rm -f "$out/fpengine-runtime.json"
    fi
    sync
    rm -f "$journal"
    sync
    echo "publish-helper-runtime: restored the previous runtime in $out after an unfinished publish" >&2
  elif [[ -e "$out/.fpengine.old" && ! -e "$out/fpengine" ]]; then
    mv "$out/.fpengine.old" "$out/fpengine"
  fi
  # Without a journal the last publish committed, so only its leftovers remain.
  rm -rf "$out/.fpengine.old" "$out/.fpengine-runtime.json.old" "$out/.fpengine-runtime.json.new" "$journal.tmp"
}

publish() {
  local out=$1 runtime=$2 manifest=$3
  local journal="$out/.publish-journal" had_runtime=0 had_manifest=0
  recover "$out"
  [[ -d "$runtime" && -f "$manifest" ]] || { echo "publish-helper-runtime: $runtime or $manifest is missing" >&2; exit 1; }
  [[ -e "$out/fpengine" ]] && had_runtime=1
  [[ -e "$out/fpengine-runtime.json" ]] && had_manifest=1
  # Stage the manifest next to its destination so the final switch is a rename on one volume.
  cp "$manifest" "$out/.fpengine-runtime.json.new"
  echo "$had_runtime $had_manifest" >"$journal.tmp"
  sync
  mv "$journal.tmp" "$journal"
  sync
  trap 'recover "$out"; exit 130' INT TERM
  step() {
    "$@" || {
      echo "publish-helper-runtime: '$*' failed; restoring the previous runtime" >&2
      recover "$out"
      exit 1
    }
  }
  if [[ $had_runtime == 1 ]]; then step mv "$out/fpengine" "$out/.fpengine.old"; fi
  if [[ $had_manifest == 1 ]]; then step mv "$out/fpengine-runtime.json" "$out/.fpengine-runtime.json.old"; fi
  step mv "$runtime" "$out/fpengine"
  step mv "$out/.fpengine-runtime.json.new" "$out/fpengine-runtime.json"
  sync
  rm -f "$journal" # commit point
  sync
  trap - INT TERM
  rm -rf "$out/.fpengine.old" "$out/.fpengine-runtime.json.old"
}

case "${1:-}" in
  --recover) [[ $# -eq 2 ]] || usage; recover "$2" ;;
  -*|'') usage ;;
  *) [[ $# -eq 3 ]] || usage; publish "$1" "$2" "$3" ;;
esac
