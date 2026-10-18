#!/usr/bin/env bash
# Self-contained; never removes category roots, retained evidence or releases.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
ACTION=inspect CATEGORY=cache ID="" APPLY=0
die() { echo "FAIL: $*" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-directory) ROOT=${2-}; shift;;
    --action) ACTION=${2-}; shift;;
    --category) CATEGORY=${2-}; shift;;
    --id) ID=${2-}; shift;;
    --apply) APPLY=1;;
    *) die 'Unknown artifact option';;
  esac
  shift
done
case "$ACTION" in create|inspect|clean) ;; *) die 'Unknown action';; esac
case "$CATEGORY" in cache|runs|evidence|releases) ;; *) die 'Unknown category';; esac
[ "$APPLY" = 0 ] || [ "$ACTION" = clean ] || die '--apply is only valid with clean'
if [ -z "$ID" ] && [ "$ACTION" = create ]; then ID=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n'); fi
[[ "$ID" =~ ^[a-f0-9]{32}$ ]] || die 'An exact lowercase hexadecimal run id is required'
ROOT=$(cd -P -- "$ROOT" && pwd -P) || die 'Project directory does not exist'
BASE="$ROOT/artifacts/$CATEGORY" ENTRY="$ROOT/artifacts/$CATEGORY/$ID"
for boundary in "$ROOT/artifacts" "$BASE" "$ENTRY"; do
  [ ! -L "$boundary" ] || die 'Artifact boundary contains a symlink'
  [ ! -e "$boundary" ] || [ -d "$boundary" ] || die 'Artifact boundary is not a directory'
done
marker() { printf 'devsetup-artifact-v1\ncategory\t%s\nid\t%s\n' "$CATEGORY" "$ID"; }
if [ "$ACTION" = create ]; then
  [ ! -e "$ENTRY" ] || die 'Artifact already exists; preserve it'
  mkdir -p -- "$BASE"
  mkdir -- "$ENTRY"
  (set -C; marker > "$ENTRY/.devsetup-owned")
  printf '%s\n' "$ENTRY"; exit 0
fi
[ -d "$ENTRY" ] || die 'Artifact does not exist'
if [ -n "$(find "$ENTRY" \( ! -type d -a ! -type f \) -print)" ]; then die 'Artifact tree contains a symlink or special file'; fi
if [ -n "$(find "$ENTRY" -name .git -print)" ]; then die 'Artifact tree contains repository metadata'; fi
cmp -s "$ENTRY/.devsetup-owned" <(marker) || die 'Ownership marker is absent or does not match'
if [ "$ACTION" = inspect ]; then printf '%s\n' "$ENTRY"; exit 0; fi
case "$CATEGORY" in cache|runs) ;; *) die 'Evidence and releases are retained';; esac
if [ -e "$ROOT/.git" ]; then
  tracked=$(git -C "$ROOT" ls-files -- "artifacts/$CATEGORY/$ID") || die 'Could not inspect tracked files'
  [ -z "$tracked" ] || die 'Artifact contains tracked files'
fi
[ ! -e "$ENTRY/.workflow-lock" ] || die 'Workflow lock exists; preserve the run'
if [ "$CATEGORY" = runs ] && [ -f "$ENTRY/state.txt" ] && [ "$(cat "$ENTRY/state.txt")" != restored ]; then
  die 'Workflow is not restored; preserve its recovery information'
fi
size=$(du -sk "$ENTRY")
printf 'Disposable artifact: %s (%s KiB allocated)\n' "$ENTRY" "${size%%[[:space:]]*}"
if [ "$APPLY" = 1 ]; then
  # ENTRY is an exact owned child of the checked category; never delete BASE/ROOT.
  rm -rf -- "$ENTRY"
  [ ! -e "$ENTRY" ] || die 'Artifact removal did not complete'
  echo 'Removed the selected owned artifact.'
else echo 'Preview only. Repeat the same selection with --apply to remove it.'; fi
