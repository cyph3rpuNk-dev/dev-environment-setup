#!/usr/bin/env bash
# Temporary fixtures only: no compiler, installer or user/system configuration.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
FIXTURE=$(mktemp -d)
FIXTURE=$(cd -- "$FIXTURE" && pwd -P)
cleanup() { [ ! -L "$FIXTURE" ] && [ "$(cd -- "$FIXTURE" && pwd -P)" = "$FIXTURE" ] && rm -rf -- "$FIXTURE"; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
PROJECT="$FIXTURE/project"
mkdir -p "$PROJECT/scripts" "$FIXTURE/bin"
cat > "$FIXTURE/bin/rustup" <<'MOCK'
#!/bin/sh
[ "$RUSTUP_AUTO_INSTALL" = 0 ] || exit 91
[ "$PWD" = / ] || exit 92
printf 'fixture-target\n'
MOCK
cat > "$FIXTURE/bin/cargo" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$EVENTS"
MOCK
chmod +x "$FIXTURE/bin/rustup" "$FIXTURE/bin/cargo"
export EVENTS="$FIXTURE/events"
printf '# inert fixture\n' > "$PROJECT/Cargo.toml"
printf '# inert fixture\n' > "$PROJECT/Cargo.lock"
printf '[toolchain]\nchannel = "fixture-missing"\n' > "$PROJECT/rust-toolchain.toml"
printf '# devsetup-requirements-v1\ncommand\tcargo\tall\nrust-target\tfixture-target\tall\nfile\tCargo.lock\tall\n' > "$PROJECT/dev-requirements.tsv"
check_project() { PATH="$FIXTURE/bin:$PATH" bash "$ROOT/scripts/check-project.sh" --project-directory "$PROJECT" --smoke-build --target fixture-target; }
check_project > /dev/null
grep -qx 'build --locked --target fixture-target' "$EVENTS" || fail 'smoke build not explicit and locked'
: > "$EVENTS"
printf '# devsetup-requirements-v1\ncommand\tmissing-fixture-command-884\tall' > "$PROJECT/dev-requirements.tsv"
if check_project > /dev/null; then fail 'missing prerequisites accepted'; fi
[ ! -s "$EVENTS" ] || fail 'build ran despite missing prerequisite on a non-newline-terminated final row'
printf '# devsetup-requirements-v1\nfile\t../escape\tall\n' > "$PROJECT/dev-requirements.tsv"
if check_project > /dev/null 2>&1; then fail 'manifest traversal accepted'; fi
[ ! -s "$EVENTS" ] || fail 'invalid manifest invoked a build'
pass 'Project prerequisite failures prevent builds; valid smoke build uses mocked Cargo'
artifact() { bash "$ROOT/scripts/manage-artifacts.sh" --project-directory "$PROJECT" "$@"; }
ID=11111111111111111111111111111111
ENTRY=$(artifact --action create --category cache --id "$ID")
printf fixture > "$ENTRY/inert.txt"
artifact --action clean --category cache --id "$ID" > /dev/null
[ -f "$ENTRY/inert.txt" ] || fail 'preview deleted files'
artifact --action clean --category cache --id "$ID" --apply > /dev/null
[ ! -e "$ENTRY" ] || fail 'explicit cleanup did not delete owned cache'
for category in evidence releases; do
  ENTRY=$(artifact --action create --category "$category" --id "$ID")
  if artifact --action clean --category "$category" --id "$ID" --apply > /dev/null 2>&1; then fail 'retained artifact deleted'; fi
  [ -d "$ENTRY" ] || fail 'retained artifact lost'
done
ENTRY=$(artifact --action create --category cache --id "$ID")
printf wrong > "$ENTRY/.devsetup-owned"
if artifact --action clean --category cache --id "$ID" --apply > /dev/null 2>&1; then fail 'wrong ownership accepted'; fi
if artifact --action clean --category cache --id ../escape --apply > /dev/null 2>&1; then fail 'traversal accepted'; fi
printf 'devsetup-artifact-v1\ncategory\tcache\nid\t%s\n' "$ID" > "$ENTRY/.devsetup-owned"
# Symlinks may be unavailable in Git Bash; native Linux/macOS CI exercises this.
mkdir "$FIXTURE/outside"
if ln -s "$FIXTURE/outside" "$ENTRY/link" 2>/dev/null && [ -L "$ENTRY/link" ]; then
  if artifact --action inspect --category cache --id "$ID" > /dev/null 2>&1; then fail 'symlink accepted'; fi
  rm -- "$ENTRY/link"
else echo 'SKIP: real symlinks unavailable for artifact fixture'; fi
pass 'Artifact deletion requires explicit application, exact ownership and a disposable category'
cp "$ROOT/scripts/manage-artifacts.sh" "$PROJECT/scripts/"
git init --quiet "$PROJECT"
cp "$ROOT/templates/foundation/run-workflow.sh.template" "$PROJECT/scripts/run-workflow.sh"
workflow() { bash "$PROJECT/scripts/run-workflow.sh" "$@"; }
if workflow --phase start > /dev/null 2>&1; then fail 'unconfigured workflow ran'; fi
[ ! -d "$PROJECT/artifacts/runs" ] || fail 'unconfigured workflow created a run'
sed -e 's/^CONFIGURED=0$/CONFIGURED=1/' \
  -e 's|^on_start().*|on_start() { printf started > "$1/started.flag"; }|' \
  -e 's|^on_collect().*|on_collect() { return 7; }|' \
  -e 's|^on_restore().*|on_restore() { printf restored > "$1/restored.flag"; }|' \
  "$ROOT/templates/foundation/run-workflow.sh.template" > "$PROJECT/scripts/run-workflow.sh"
workflow --phase start > /dev/null
for run in "$PROJECT/artifacts/runs/"*; do RUN_ID=${run##*/}; RUN_PATH="$run"; done
if workflow --phase collect --run-id "$RUN_ID" > /dev/null 2>&1; then fail 'failed collection accepted'; fi
grep -qx collect-failed "$RUN_PATH/state.txt" || fail 'collection failure not recorded'
mkdir "$RUN_PATH/.workflow-lock"
if artifact --action clean --category runs --id "$RUN_ID" --apply > /dev/null 2>&1; then fail 'locked workflow removed'; fi
rmdir "$RUN_PATH/.workflow-lock"
if artifact --action clean --category runs --id "$RUN_ID" --apply > /dev/null 2>&1; then fail 'unrestored recovery information deleted'; fi
workflow --phase restore --run-id "$RUN_ID" > /dev/null
[ -f "$RUN_PATH/restored.flag" ] || fail 'restore unavailable after collection failure'
if workflow --phase collect --run-id "$RUN_ID" > /dev/null 2>&1; then fail 'collection after restore accepted'; fi
grep -qx restored "$RUN_PATH/state.txt" || fail 'invalid transition changed state'
[ -f "$RUN_PATH/metadata.tsv" ] || fail 'run metadata missing'
grep -q unborn-or-unavailable "$RUN_PATH/metadata.tsv" || fail 'unborn repository not labelled'
pass 'Workflow failures retain evidence and allow restoration; out-of-order phases are refused'
git -C "$PROJECT" -c core.autocrlf=false -c core.hooksPath="$FIXTURE/no-hooks" add -- "artifacts/cache/$ID/.devsetup-owned"
if artifact --action clean --category cache --id "$ID" --apply > /dev/null 2>&1; then fail 'tracked artifact deleted'; fi
[ -d "$ENTRY" ] || fail 'tracked artifact lost'
pass 'Cleanup preserves tracked files even inside an owned disposable entry'
DEVSETUP_KERNEL=Linux DEVSETUP_PROC_VERSION=/dev/null bash "$ROOT/new-project.sh" --name helper-tool --parent "$FIXTURE/scaffold" --environment linux --maintenance-helpers > /dev/null
for file in dev-requirements.tsv scripts/check-project.sh scripts/manage-artifacts.sh scripts/run-workflow.sh; do
  [ -f "$FIXTURE/scaffold/helper-tool/$file" ] || fail 'maintenance scaffold incomplete'
done
bash "$FIXTURE/scaffold/helper-tool/scripts/check-project.sh" > /dev/null
pass 'Optional maintenance scaffold is self-contained'
