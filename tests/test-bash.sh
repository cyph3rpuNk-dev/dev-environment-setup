#!/usr/bin/env bash
# Run only in temporary fixtures with package managers, auth and agents mocked.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/profile"
# shellcheck source=helpers/install-browser-bridge.sh
. "$ROOT/helpers/install-browser-bridge.sh"
sudo() { "$@"; }
printf 'custom browser\n' > "$TEST_ROOT/bin/xdg-open"
install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/bin" "$TEST_ROOT/profile"
grep -qx 'custom browser' "$TEST_ROOT/bin/xdg-open" || fail 'custom xdg-open changed'
pass 'Bridge installation preserves existing xdg-open'
sudo() { fail 'sudo called on already completed bridge installation'; }
install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/bin" "$TEST_ROOT/profile"
pass 'Repeated bridge installation performs no privileged writes'
printf 'custom bridge\n' > "$TEST_ROOT/bin/wslview"
if install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/bin" "$TEST_ROOT/profile"; then fail 'custom bridge replaced'; fi
grep -qx 'custom bridge' "$TEST_ROOT/bin/wslview" || fail 'custom bridge contents changed'
pass 'Custom bridge is rejected without modification'
mkdir -p "$TEST_ROOT/failing-bin" "$TEST_ROOT/failing-profile"
sudo() { return 42; }
if install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/failing-bin" "$TEST_ROOT/failing-profile"; then fail 'failed installation reported success'; fi
pass 'Bridge propagates installation failures'
# Obtain the exact old shipped fixture without executing it.
awk '/^#!\/usr\/bin\/env bash$/ { n++ } n==2 { if ($0=="LEGACY") exit; print }' "$ROOT/helpers/install-browser-bridge.sh" > "$TEST_ROOT/bin/wslview"
sudo() { "$@"; }
install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/bin" "$TEST_ROOT/profile"
cmp -s "$ROOT/helpers/wslview.sh" "$TEST_ROOT/bin/wslview" || fail 'legacy upgrade failed'
pass 'Exact legacy bridge upgrades to the safe implementation'
if bash "$ROOT/helpers/wslview.sh" 'file:///sensitive'; then fail 'non-web URL accepted'; fi
pass 'Bash bridge rejects non-web URLs before invoking Windows'

# Full bootstrap fixtures: every external provisioning/auth command is mocked.
mkdir -p "$TEST_ROOT/mock-bin" "$TEST_ROOT/user"
export TEST_EVENTS="$TEST_ROOT/events" TEST_EXTENSIONS="$TEST_ROOT/extensions"
: > "$TEST_EVENTS"; : > "$TEST_EXTENSIONS"
cat > "$TEST_ROOT/mock-bin/mock" <<'MOCK'
#!/usr/bin/env bash
name=${0##*/}
printf '%s\n' "$name $*" >> "$TEST_EVENTS"
case "$name" in
  sudo|dnf) echo 'Unexpected privileged command in bootstrap test' >&2; exit 90 ;;
  rpm) exit 0 ;;
  rustup) printf 'rustfmt clippy\n' ;;
  rustc) printf 'rustc 1.85.0\n' ;;
  code)
    if [ "$1" = --list-extensions ]; then cat "$TEST_EXTENSIONS"
    else printf '%s\n' "$2" >> "$TEST_EXTENSIONS"; fi ;;
  gh)
    if [ "$2" = token ]; then
      case "${TEST_TOKEN_MODE:-ok}" in empty) exit 0;; fail) exit 1;; esac
      printf 'fake-token\n'
    else printf 'workflow\n'; fi ;;
  claude) printf 'context7 github\n' ;;
  curl)
    # A partial downloaded script must never be executed after curl fails.
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then shift; printf 'touch "%s"\n' "$TEST_EVENTS.executed" > "$1"; break; fi
      shift
    done
    exit 22 ;;
  codex)
    if [ "${TEST_HELPER:-0}" = 1 ]; then
      [ "${GITHUB_MCP_PAT:-}" = fake-token ] || exit 91
      exit 7
    fi ;;
  *) exit 0 ;;
esac
MOCK
for command in sudo dnf rpm rustup rustc cargo code gh claude codex git curl cargo-binstall cargo-nextest cargo-audit cargo-machete cargo-deny bacon typos; do
  cp "$TEST_ROOT/mock-bin/mock" "$TEST_ROOT/mock-bin/$command"
  chmod +x "$TEST_ROOT/mock-bin/$command"
done
run_bootstrap() {
  # HOME is set only in this child environment; the test runner's home is untouched.
  env HOME="$TEST_ROOT/user" PATH="$TEST_ROOT/mock-bin:/usr/bin:/bin" bash "$ROOT/bootstrap-wsl.sh" "$@"
}
run_bootstrap --no-dnf > "$TEST_ROOT/base.log"
[ ! -e "$TEST_ROOT/user/.codex" ] && [ ! -e "$TEST_ROOT/user/.claude" ] || fail 'base wrote agent configuration'
if grep -Eq '^(rustup|rustc|cargo|claude|codex|curl) |rust-analyzer|gtk4-devel|systemd-devel|libadwaita-devel' "$TEST_EVENTS"; then fail 'base invoked optional stack or agents'; fi
: > "$TEST_EVENTS"
if run_bootstrap --stack=unknown > "$TEST_ROOT/invalid.log" 2>&1; then fail 'unknown stack accepted'; fi
[ ! -s "$TEST_EVENTS" ] || fail 'invalid stack performed work'
pass 'Base excludes optional stacks and agents; invalid stack fails before work'
run_bootstrap --no-dnf --stack=rust --configure-agents > "$TEST_ROOT/first.log"
grep -q '^rustup component add' "$TEST_EVENTS" || fail 'Rust selection skipped components'
grep -q 'rust-analyzer' "$TEST_EVENTS" || fail 'Rust selection skipped extensions'
cp "$TEST_ROOT/user/.codex/config.toml" "$TEST_ROOT/config.before"
cp "$TEST_ROOT/user/.claude/settings.json" "$TEST_ROOT/settings.before"
run_bootstrap --no-dnf --stack=rust --configure-agents > "$TEST_ROOT/second.log"
cmp -s "$TEST_ROOT/config.before" "$TEST_ROOT/user/.codex/config.toml" || fail 'Codex config changed on rerun'
cmp -s "$TEST_ROOT/settings.before" "$TEST_ROOT/user/.claude/settings.json" || fail 'Claude config changed on rerun'
[ "$(grep -c '^\[mcp_servers.github\]' "$TEST_ROOT/user/.codex/config.toml")" -eq 1 ] || fail 'GitHub table duplicated'
if grep -Eq '^(sudo|dnf) ' "$TEST_EVENTS"; then fail '--no-dnf invoked privilege escalation'; fi
pass 'First run and rerun preserve configuration and honor --no-dnf'
: > "$TEST_EVENTS"
run_bootstrap --doctor --stack=rust --configure-agents > "$TEST_ROOT/doctor.log"
cmp -s "$TEST_ROOT/config.before" "$TEST_ROOT/user/.codex/config.toml" || fail 'Doctor changed config'
if grep -Eq '^(sudo|dnf|curl) |^cargo (install|binstall)|^code --install|^claude mcp add|^gh auth setup-git' "$TEST_EVENTS"; then fail 'Doctor invoked mutation'; fi
pass 'Doctor performs no provisioning or configuration writes'
if run_bootstrap --no-dnf --install-browser-bridge > "$TEST_ROOT/conflict.log" 2>&1; then fail 'conflicting options accepted'; fi
pass 'Conflicting privilege options fail before provisioning'
rm -- "$TEST_ROOT/mock-bin/rustup"
if run_bootstrap --no-dnf --stack=rust > "$TEST_ROOT/download.log" 2>&1; then fail 'download failure returned success'; fi
[ ! -e "$TEST_EVENTS.executed" ] || fail 'partial installer executed'
grep -q 'rustup install failed' "$TEST_ROOT/download.log" || fail 'download failure not diagnosed'
pass 'Failed partial download is not executed and bootstrap returns failure'

for mode in ok empty fail; do
  result=0
  env PATH="$TEST_ROOT/mock-bin:/usr/bin:/bin" TEST_HELPER=1 TEST_TOKEN_MODE="$mode" \
    bash "$ROOT/helpers/codex-with-github-mcp.sh" > "$TEST_ROOT/helper.log" 2>&1 || result=$?
  if [ "$mode" = ok ]; then [ "$result" -eq 7 ] || fail 'helper lost child exit code'
  else [ "$result" -eq 1 ] || fail 'helper accepted missing token'; fi
done
pass 'Bash credential helper passes child status and rejects absent tokens'

mkdir -p "$TEST_ROOT/project/scripts"
sed -e 's/{{FORMAT_COMMAND}}/false/' -e 's/{{LINT_COMMAND}}/missing-audit-command-747/' \
    -e 's/{{TEST_COMMAND}}/touch continued/' "$ROOT/templates/foundation/check.sh.template" > "$TEST_ROOT/project/scripts/check.sh"
result=0
bash "$TEST_ROOT/project/scripts/check.sh" > "$TEST_ROOT/gate.log" 2>&1 || result=$?
[ "$result" -eq 2 ] && [ -f "$TEST_ROOT/project/continued" ] || fail 'Bash gate status, continuation or working directory failed'
pass 'Bash gate counts failures, continues and uses repository root'
echo 'Bash regressions passed.'
