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
unset -f sudo

# Full bootstrap fixtures: every external provisioning/auth command is mocked, and
# the platform is described by fixture files rather than read from this machine.
mkdir -p "$TEST_ROOT/mock-bin" "$TEST_ROOT/user" "$TEST_ROOT/os"
printf 'ID=fedora\nPRETTY_NAME="Fedora Linux 44"\n' > "$TEST_ROOT/os/fedora"
printf 'ID=ubuntu\nID_LIKE=debian\nPRETTY_NAME="Ubuntu 24.04 LTS"\n' > "$TEST_ROOT/os/ubuntu"
printf 'ID=arch\nPRETTY_NAME="Arch Linux"\n' > "$TEST_ROOT/os/arch"
printf 'Linux version 6.8.0-generic (buildd@ubuntu) #1 SMP\n' > "$TEST_ROOT/os/native"
printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 #1 SMP\n' > "$TEST_ROOT/os/wsl"
export TEST_EVENTS="$TEST_ROOT/events" TEST_EXTENSIONS="$TEST_ROOT/extensions"
: > "$TEST_EVENTS"; : > "$TEST_EXTENSIONS"
cat > "$TEST_ROOT/mock-bin/mock" <<'MOCK'
#!/usr/bin/env bash
name=${0##*/}
printf '%s\n' "$name $*" >> "$TEST_EVENTS"
missing() { case " ${TEST_MISSING_PKGS:-} " in *" $1 "*) return 0;; esac; return 1; }
case "$name" in
  sudo)
    [ "${TEST_ALLOW_SUDO:-0}" = 1 ] || { echo 'Unexpected privileged command in bootstrap test' >&2; exit 90; }
    exec "$@" ;;
  dnf|apt-get)
    [ "${TEST_ALLOW_SUDO:-0}" = 1 ] || { echo 'Unexpected package manager call' >&2; exit 90; } ;;
  rpm) if missing "$2"; then exit 1; fi ;;
  dpkg-query) if missing "${!#}"; then exit 1; fi; printf 'install ok installed' ;;
  rustup) printf 'rustfmt clippy\n' ;;
  rustc) printf 'rustc 1.85.0\n' ;;
  uv) printf 'uv 0.9.0\n' ;;
  code)
    if [ "$1" = --list-extensions ]; then cat "$TEST_EXTENSIONS"
    else printf '%s\n' "$2" >> "$TEST_EXTENSIONS"; fi ;;
  gh)
    version=${TEST_GH_VERSION:-2.45.0}
    if [ "$1" = --version ]; then printf 'gh version %s (2026-01-01)\n' "$version"; exit 0; fi
    if [ "$2" = token ]; then
      case "${TEST_TOKEN_MODE:-ok}" in empty) exit 0;; fail) exit 1;; esac
      printf 'fake-token\n'; exit 0
    fi
    # Builds before 2.40 reject --active, as the real CLI does.
    case "$version $*" in 2.[0-3][0-9].*--active*) echo 'unknown flag: --active' >&2; exit 1;; esac
    printf 'workflow\n' ;;
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
for command in sudo dnf apt-get rpm dpkg-query rustup rustc cargo uv code gh claude codex git curl cargo-binstall cargo-nextest cargo-audit cargo-machete cargo-deny bacon typos; do
  cp "$TEST_ROOT/mock-bin/mock" "$TEST_ROOT/mock-bin/$command"
  chmod +x "$TEST_ROOT/mock-bin/$command"
done
# run_bootstrap OS KERNEL [options]: HOME and PATH are set only for the child.
run_bootstrap() {
  local os="$1" kernel="$2"; shift 2
  env HOME="$TEST_ROOT/user" PATH="$TEST_ROOT/mock-bin:/usr/bin:/bin" \
    DEVSETUP_OS_RELEASE="$TEST_ROOT/os/$os" DEVSETUP_PROC_VERSION="$TEST_ROOT/os/$kernel" \
    bash "$ROOT/bootstrap-linux.sh" "$@"
}

run_bootstrap fedora wsl --no-dnf > "$TEST_ROOT/base.log"
[ ! -e "$TEST_ROOT/user/.codex" ] && [ ! -e "$TEST_ROOT/user/.claude" ] || fail 'base wrote agent configuration'
if grep -Eq '^(rustup|rustc|cargo|uv|claude|codex|curl) |rust-analyzer|ms-python|gtk4-devel|systemd-devel|libadwaita-devel' "$TEST_EVENTS"; then fail 'base invoked optional stack or agents'; fi
grep -q 'WSL detected (Fedora Linux 44)' "$TEST_ROOT/base.log" || fail 'WSL platform not reported'
grep -q 'package manager: dnf' "$TEST_ROOT/base.log" || fail 'dnf not selected for Fedora'
: > "$TEST_EVENTS"
if run_bootstrap fedora native --stack=unknown > "$TEST_ROOT/invalid.log" 2>&1; then fail 'unknown stack accepted'; fi
[ ! -s "$TEST_EVENTS" ] || fail 'invalid stack performed work'
pass 'Base excludes optional stacks and agents; invalid stack fails before work'
run_bootstrap fedora wsl --no-sudo --stack=rust --configure-agents > "$TEST_ROOT/first.log"
grep -q '^rustup component add' "$TEST_EVENTS" || fail 'Rust selection skipped components'
grep -q 'rust-analyzer' "$TEST_EVENTS" || fail 'Rust selection skipped extensions'
cp "$TEST_ROOT/user/.codex/config.toml" "$TEST_ROOT/config.before"
cp "$TEST_ROOT/user/.claude/settings.json" "$TEST_ROOT/settings.before"
run_bootstrap fedora wsl --no-sudo --stack=rust --configure-agents > "$TEST_ROOT/second.log"
cmp -s "$TEST_ROOT/config.before" "$TEST_ROOT/user/.codex/config.toml" || fail 'Codex config changed on rerun'
cmp -s "$TEST_ROOT/settings.before" "$TEST_ROOT/user/.claude/settings.json" || fail 'Claude config changed on rerun'
[ "$(grep -c '^\[mcp_servers.github\]' "$TEST_ROOT/user/.codex/config.toml")" -eq 1 ] || fail 'GitHub table duplicated'
if grep -Eq '^(sudo|dnf|apt-get) ' "$TEST_EVENTS"; then fail '--no-sudo invoked privilege escalation'; fi
pass 'First run and rerun preserve configuration and honor --no-sudo'
: > "$TEST_EVENTS"
run_bootstrap fedora wsl --doctor --stack=rust --configure-agents > "$TEST_ROOT/doctor.log"
cmp -s "$TEST_ROOT/config.before" "$TEST_ROOT/user/.codex/config.toml" || fail 'Doctor changed config'
if grep -Eq '^(sudo|dnf|apt-get|curl) |^cargo (install|binstall)|^code --install|^claude mcp add|^gh auth setup-git' "$TEST_EVENTS"; then fail 'Doctor invoked mutation'; fi
grep -q 'src does not exist yet' "$TEST_ROOT/doctor.log" || fail 'WSL doctor did not report project location'
pass 'Doctor performs no provisioning or configuration writes'
if run_bootstrap fedora wsl --no-sudo --install-browser-bridge > "$TEST_ROOT/conflict.log" 2>&1; then fail 'conflicting options accepted'; fi
pass 'Conflicting privilege options fail before provisioning'

# Native Linux must not need or touch anything WSL-specific.
: > "$TEST_EVENTS"
result=0
run_bootstrap ubuntu native --install-browser-bridge > "$TEST_ROOT/native-bridge.log" 2>&1 || result=$?
[ "$result" -eq 2 ] && [ ! -s "$TEST_EVENTS" ] || fail 'browser bridge accepted on native Linux'
run_bootstrap ubuntu native --doctor > "$TEST_ROOT/native.log"
grep -q 'native Linux (Ubuntu 24.04 LTS)' "$TEST_ROOT/native.log" || fail 'native Linux not reported'
grep -q 'package manager: apt' "$TEST_ROOT/native.log" || fail 'apt not selected for Ubuntu'
grep -q 'browser bridge is WSL-only' "$TEST_ROOT/native.log" || fail 'native Linux looked for the WSL bridge'
if grep -q 'WSL kernel' "$TEST_ROOT/native.log"; then fail 'native Linux reported WSL'; fi
grep -q '^dpkg-query' "$TEST_EVENTS" || fail 'apt systems not checked with dpkg-query'
if grep -q '^rpm ' "$TEST_EVENTS"; then fail 'apt system queried rpm'; fi
pass 'Native Linux is detected and never offered the WSL bridge'

# Missing packages are installed with the distribution's own package manager.
: > "$TEST_EVENTS"
TEST_ALLOW_SUDO=1 TEST_MISSING_PKGS=gh run_bootstrap ubuntu native > "$TEST_ROOT/apt.log"
grep -q '^apt-get update' "$TEST_EVENTS" && grep -q '^apt-get install -y gh$' "$TEST_EVENTS" || fail 'apt did not install the missing package'
if grep -q '^dnf ' "$TEST_EVENTS"; then fail 'apt system invoked dnf'; fi
: > "$TEST_EVENTS"
TEST_ALLOW_SUDO=1 TEST_MISSING_PKGS=gh run_bootstrap fedora native > "$TEST_ROOT/dnf.log"
grep -q '^dnf install -y gh$' "$TEST_EVENTS" || fail 'dnf did not install the missing package'
if grep -q '^apt-get ' "$TEST_EVENTS"; then fail 'dnf system invoked apt-get'; fi
pass 'Missing packages use apt on Debian/Ubuntu and dnf on Fedora'
result=0
TEST_MISSING_PKGS=build-essential run_bootstrap ubuntu native --check --stack=rust > "$TEST_ROOT/apt-rust.log" || result=$?
[ "$result" -ne 0 ] && grep -q 'build-essential is missing' "$TEST_ROOT/apt-rust.log" || fail 'missing Rust build packages not reported on apt'
: > "$TEST_EVENTS"
run_bootstrap arch native > "$TEST_ROOT/arch.log"
grep -q "unsupported distribution 'arch'" "$TEST_ROOT/arch.log" || fail 'unsupported distribution not reported'
if grep -Eq '^(sudo|dnf|apt-get|rpm|dpkg-query) ' "$TEST_EVENTS"; then fail 'unsupported distribution invoked a package manager'; fi
pass 'Rust build packages follow the distribution; unknown distributions are never guessed'

# Stacks can be combined; Python adds uv and its editor extensions.
: > "$TEST_EVENTS"; : > "$TEST_EXTENSIONS"
run_bootstrap ubuntu native --stack=rust,python > "$TEST_ROOT/multi.log"
grep -q 'rust-analyzer' "$TEST_EVENTS" && grep -q 'ms-python.python' "$TEST_EVENTS" && grep -q 'charliermarsh.ruff' "$TEST_EVENTS" || fail 'combined stacks did not add both extension sets'
grep -q 'uv 0.9.0' "$TEST_ROOT/multi.log" || fail 'uv not detected'
pass 'Rust and Python stacks combine in one run'

# An older distribution gh must not read as "not authenticated".
: > "$TEST_EVENTS"
TEST_GH_VERSION=2.23.0 run_bootstrap ubuntu native --check > "$TEST_ROOT/oldgh.log" || true
grep -q 'older than 2.40' "$TEST_ROOT/oldgh.log" || fail 'old gh not diagnosed'
grep -q 'GitHub CLI is authenticated' "$TEST_ROOT/oldgh.log" || fail 'old gh authentication misreported'
pass 'GitHub CLI older than 2.40 is diagnosed and still recognized as authenticated'

for tool in rustup uv; do
  mv "$TEST_ROOT/mock-bin/$tool" "$TEST_ROOT/$tool.saved"
done
: > "$TEST_EVENTS"
if run_bootstrap fedora native --no-sudo --stack=rust > "$TEST_ROOT/download.log" 2>&1; then fail 'download failure returned success'; fi
[ ! -e "$TEST_EVENTS.executed" ] || fail 'partial installer executed'
grep -q 'rustup install failed' "$TEST_ROOT/download.log" || fail 'download failure not diagnosed'
if run_bootstrap fedora native --no-sudo --stack=python > "$TEST_ROOT/uv-download.log" 2>&1; then fail 'uv download failure returned success'; fi
[ ! -e "$TEST_EVENTS.executed" ] || fail 'partial uv installer executed'
grep -q 'uv install failed' "$TEST_ROOT/uv-download.log" || fail 'uv download failure not diagnosed'
for tool in rustup uv; do mv "$TEST_ROOT/$tool.saved" "$TEST_ROOT/mock-bin/$tool"; done
pass 'Failed partial downloads are never executed and bootstrap returns failure'

: > "$TEST_EVENTS"
if env DEVSETUP_OS_RELEASE="$TEST_ROOT/os/fedora" bash "$ROOT/bootstrap-wsl.sh" --stack=unknown > /dev/null 2>&1; then fail 'wrapper accepted unknown stack'; fi
env HOME="$TEST_ROOT/user" PATH="$TEST_ROOT/mock-bin:/usr/bin:/bin" DEVSETUP_OS_RELEASE="$TEST_ROOT/os/fedora" \
  DEVSETUP_PROC_VERSION="$TEST_ROOT/os/wsl" bash "$ROOT/bootstrap-wsl.sh" --check > "$TEST_ROOT/wrapper.log"
grep -q 'WSL detected' "$TEST_ROOT/wrapper.log" || fail 'wrapper did not run the Linux bootstrap'
pass 'bootstrap-wsl.sh remains a compatible entry point'

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
cp "$ROOT/templates/foundation/check.sh.template" "$TEST_ROOT/project/scripts/unfilled.sh"
result=0
bash "$TEST_ROOT/project/scripts/unfilled.sh" > "$TEST_ROOT/unfilled.log" 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -q 'placeholders' "$TEST_ROOT/unfilled.log" || fail 'unfilled gate did not refuse to run'
pass 'Unfilled Bash gate refuses to report success'

# Scaffolder: real git in a temporary parent; stdin is never a terminal here.
NP="$TEST_ROOT/np"
new_project() { env DEVSETUP_PROC_VERSION="$TEST_ROOT/os/${NP_KERNEL:-native}" bash "$ROOT/new-project.sh" "$@" < /dev/null; }
new_project --name demo --parent "$NP" --windows-native no --linux-target yes --stack python > "$TEST_ROOT/np.log"
for f in README.md PROJECT-CHARTER.md AGENTS.md CLAUDE.md scripts/check.sh .gitattributes .gitignore .editorconfig; do
  [ -f "$NP/demo/$f" ] || fail "scaffolder did not create $f"
done
[ -x "$NP/demo/scripts/check.sh" ] || fail 'scaffolded gate is not executable'
[ "$(git -C "$NP/demo" symbolic-ref HEAD)" = refs/heads/main ] || fail 'scaffolded repository not on main'
if git -C "$NP/demo" rev-parse --verify -q HEAD > /dev/null; then fail 'scaffolder created a commit'; fi
grep -q 'Canonical development environment: LINUX' "$NP/demo/PROJECT-CHARTER.md" || fail 'environment not recorded'
grep -q 'Environment rationale: it runs on or deploys to Linux' "$NP/demo/PROJECT-CHARTER.md" || fail 'environment reason not recorded'
grep -q '{{LICENCE_OR_UNDECIDED}}' "$NP/demo/PROJECT-CHARTER.md" || fail 'undecided charter fields were filled in'
grep -q 'uv run ruff check' "$NP/demo/scripts/check.sh" && grep -qx '.venv/' "$NP/demo/.gitignore" || fail 'Python stack not applied'
if grep -q '{{[A-Z_][A-Z_]*}}' "$NP/demo/scripts/check.sh"; then fail 'stack gate kept placeholders'; fi
if grep -rl $'\r' "$NP/demo" --exclude-dir=.git | grep -q .; then fail 'scaffolder wrote CRLF'; fi
pass 'Scaffolder creates an uncommitted Linux repository and records the environment and reason'
new_project --name plain --parent "$NP" --environment linux --no-claude > /dev/null
[ ! -e "$NP/plain/CLAUDE.md" ] || fail '--no-claude ignored'
result=0; (cd "$NP/plain" && ./scripts/check.sh) > "$TEST_ROOT/np-gate.log" 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -q 'placeholders' "$TEST_ROOT/np-gate.log" || fail 'unfilled scaffolded gate did not refuse'
pass 'Scaffolded gate without a chosen stack refuses to run'
result=0; new_project --name wintool --parent "$NP" --windows-native yes --linux-target no > "$TEST_ROOT/np-win.log" || result=$?
[ "$result" -eq 3 ] && [ ! -e "$NP/wintool" ] && grep -q 'new-project.ps1' "$TEST_ROOT/np-win.log" || fail 'Windows project was created on Linux'
printf 'keep\n' > "$NP/demo/sentinel"
result=0; new_project --name demo --parent "$NP" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -qx keep "$NP/demo/sentinel" || fail 'scaffolder touched an existing project'
result=0; new_project --name ../escape --parent "$NP" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && [ ! -e "$TEST_ROOT/escape" ] || fail 'unsafe name accepted'
result=0; new_project --name asks --parent "$NP" > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && [ ! -e "$NP/asks" ] || fail 'missing answers were guessed'
result=0; NP_KERNEL=wsl new_project --name onwindows --parent /mnt/c/src --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] || fail 'WSL project accepted on the Windows filesystem'
pass 'Scaffolder refuses the wrong platform, existing projects, unsafe names, guesses and /mnt in WSL'
echo 'Bash regressions passed.'
