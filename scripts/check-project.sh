#!/usr/bin/env bash
# Copy into scripts/. No installs; compilation requires --smoke-build --target.
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 1
SMOKE=0 TARGET=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-directory) ROOT=${2-}; [ -n "$ROOT" ] || exit 1; shift;;
    --smoke-build) SMOKE=1;;
    --target) TARGET=${2-}; [ -n "$TARGET" ] || exit 1; shift;;
    *) echo 'Unknown project-check option' >&2; exit 1;;
  esac
  shift
done
cd -- "$ROOT" || exit 1
export RUSTUP_AUTO_INSTALL=0
FAIL=0 COUNT=0
MANIFEST=dev-requirements.tsv
if [ -f "$MANIFEST" ]; then
  # Validate the entire manifest before invoking any prerequisite command.
  awk -F '\t' '
    NR==1 { if ($0 != "# devsetup-requirements-v1") exit 1; next }
    /^#/ || /^[[:space:]]*$/ { next }
    NF!=3 || $3 !~ /^(all|windows|unix)$/ { exit 1 }
    $1 ~ /^(command|rust-target|pkg-config)$/ { if ($2 !~ /^[A-Za-z0-9][A-Za-z0-9._+-]*$/) exit 1; next }
    $1=="windows-sdk" { if ($3!="windows" || $2 !~ /^10[.]0[.][0-9]+[.][0-9]+$/) exit 1; next }
    $1=="file" { if ($2=="" || $2 ~ /^[\/\\]/ || $2 ~ /:/ || $2 ~ /(^|[\/\\])[.][.]([\/\\]|$)/) exit 1; next }
    { exit 1 }
    END { if (NR==0) exit 1 }
  ' "$MANIFEST" || { echo 'FAIL: invalid requirements manifest' >&2; exit 1; }
  while IFS="$(printf '\t')" read -r kind value scope || [ -n "${kind-}${value-}${scope-}" ]; do
    case "$kind" in ''|\#*) continue;; esac
    [[ "$kind" =~ ^[[:space:]]*$ ]] && continue
    COUNT=$((COUNT + 1))
    # This entry point is for native Linux, macOS and WSL; Windows has its own script.
    [ "$scope" != windows ] || continue
    ready=0
    case "$kind" in
      command) command -v "$value" >/dev/null 2>&1 && ready=1;;
      file) [ -f "$value" ] && ready=1;;
      rust-target)
        if command -v rustup >/dev/null 2>&1; then
          installed=$(cd / && rustup target list --installed) && { printf '%s\n' "$installed" | grep -Fxq -- "$value"; } && ready=1
        fi;;
      pkg-config) command -v pkg-config >/dev/null 2>&1 && pkg-config --exists "$value" && ready=1;;
    esac
    if [ "$ready" = 1 ]; then printf 'ok: %s %s\n' "$kind" "$value"
    else printf 'FAIL: %s %s\n' "$kind" "$value"; FAIL=$((FAIL + 1)); fi
  done < "$MANIFEST"
fi
[ "$COUNT" != 0 ] || echo 'warn: no project requirements declared; readiness is not established'
if [ "$SMOKE" = 1 ]; then
  [ "$FAIL" = 0 ] || { echo 'FAIL: prerequisites failed; smoke build was not started'; exit 1; }
  [[ "$TARGET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'FAIL: explicit target required'; exit 1; }
  [ -f Cargo.toml ] && [ -f Cargo.lock ] || { echo 'FAIL: Cargo.toml and Cargo.lock required'; exit 1; }
  cargo build --locked --target "$TARGET" || FAIL=$((FAIL + 1))
fi
exit "$FAIL"
