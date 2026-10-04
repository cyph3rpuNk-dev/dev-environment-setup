#!/usr/bin/env bash
# Run only in temporary fixtures with package managers, auth and agents mocked.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
export TMPDIR="$TEST_ROOT"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
# Never let a developer's real Codex configuration be read or written.
unset CODEX_HOME
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
# The legacy shim's exact bytes are pinned by hash, so the helper cannot drift from
# what was once shipped.
legacy_browser_bridge > "$TEST_ROOT/bin/wslview"
if command -v sha256sum >/dev/null 2>&1; then legacy_sum=$(sha256sum < "$TEST_ROOT/bin/wslview")
else legacy_sum=$(shasum -a 256 < "$TEST_ROOT/bin/wslview"); fi
[ "${legacy_sum%% *}" = 6050f130ca1f6ee83dd3bc8078b7ad6e8c149983c9c3281096d4189364a0f80b ] || fail 'legacy bridge bytes changed'
sudo() { "$@"; }
install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/bin" "$TEST_ROOT/profile"
cmp -s "$ROOT/helpers/wslview.sh" "$TEST_ROOT/bin/wslview" || fail 'legacy upgrade failed'
pass 'Exact legacy bridge upgrades to the safe implementation'
# A reachable fake powershell.exe proves the scheme check stops before Windows runs.
mkdir -p "$TEST_ROOT/fake-ps-scheme"
printf '#!/bin/sh\ntouch "%s/ps-invoked"\n' "$TEST_ROOT" > "$TEST_ROOT/fake-ps-scheme/powershell.exe"
chmod +x "$TEST_ROOT/fake-ps-scheme/powershell.exe"
result=0
DEVSETUP_WSL_POWERSHELL="$TEST_ROOT/fake-ps-scheme/powershell.exe" \
  bash "$ROOT/helpers/wslview.sh" 'file:///sensitive' > "$TEST_ROOT/scheme.log" 2>&1 || result=$?
[ "$result" -ne 0 ] && grep -q 'Only http and https URLs are supported' "$TEST_ROOT/scheme.log" \
  && [ ! -e "$TEST_ROOT/ps-invoked" ] || fail 'non-web URL accepted or passed to PowerShell'
pass 'Bash bridge rejects non-web URLs before invoking Windows'
# The bridge finds powershell.exe on PATH when it is not at the usual /mnt/c path.
# A fake records what it receives; the real one is never reachable here.
mkdir -p "$TEST_ROOT/fake-windows"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/ps-args"\ncat > "%s/ps-stdin"\n' "$TEST_ROOT" "$TEST_ROOT" > "$TEST_ROOT/fake-windows/powershell.exe"
chmod +x "$TEST_ROOT/fake-windows/powershell.exe"
env PATH="$TEST_ROOT/fake-windows:/usr/bin:/bin" DEVSETUP_WSL_POWERSHELL="$TEST_ROOT/no-powershell.exe" \
  bash "$ROOT/helpers/wslview.sh" 'https://example.invalid/a?b=1' || fail 'bridge did not use powershell.exe from PATH'
grep -q -- '-NoProfile -NonInteractive -Command' "$TEST_ROOT/ps-args" || fail 'bridge did not run the fixed PowerShell command'
[ "$(base64 -d < "$TEST_ROOT/ps-stdin" 2>/dev/null || base64 -D < "$TEST_ROOT/ps-stdin")" = 'https://example.invalid/a?b=1' ] || fail 'bridge did not pass the URL as base64 data'
result=0
env PATH="/usr/bin:/bin" DEVSETUP_WSL_POWERSHELL="$TEST_ROOT/no-powershell.exe" \
  bash "$ROOT/helpers/wslview.sh" 'https://example.invalid/' > "$TEST_ROOT/no-ps.log" 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -q 'powershell.exe was not found' "$TEST_ROOT/no-ps.log" || fail 'missing powershell.exe not reported'
pass 'Bridge finds powershell.exe on PATH and reports when it is missing'
# The previous (v2) bridge is an earlier toolkit version, so it upgrades in place.
mkdir -p "$TEST_ROOT/v2-bin" "$TEST_ROOT/v2-profile"
cp "$ROOT/tests/fixtures/wslview-v2.sh" "$TEST_ROOT/v2-bin/wslview"
chmod +x "$TEST_ROOT/v2-bin/wslview"
if ! PATH="$TEST_ROOT/v2-bin:$PATH" install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/v2-bin" "$TEST_ROOT/v2-profile"; then
  fail 'v2 bridge was not upgraded'
fi
cmp -s "$ROOT/helpers/wslview.sh" "$TEST_ROOT/v2-bin/wslview" || fail 'v2 bridge was not replaced with the current bridge'
# The fixture's bytes are pinned, so it cannot drift from what was shipped as v2.
if command -v sha256sum >/dev/null 2>&1; then v2_sum=$(sha256sum < "$ROOT/tests/fixtures/wslview-v2.sh")
else v2_sum=$(shasum -a 256 < "$ROOT/tests/fixtures/wslview-v2.sh"); fi
[ "${v2_sum%% *}" = 4fc721bf180d8e55dfd7389d9f673a20783e9e708ab7d990292810ff6b9faf0b ] || fail 'v2 bridge fixture bytes changed'
pass 'Previous toolkit bridge upgrades to the current version'
# Drive mount root parsing for WSL, from /etc/wsl.conf or its fixture override.
# shellcheck source=helpers/wsl-paths.sh
. "$ROOT/helpers/wsl-paths.sh"
check_root() { # check_root EXPECTED CONF_TEXT
  printf '%b' "$2" > "$TEST_ROOT/wsl.conf"
  [ "$(DEVSETUP_WSL_CONF="$TEST_ROOT/wsl.conf" wsl_drive_root)" = "$1" ] || fail "wsl.conf root not parsed as $1: $2"
}
[ "$(DEVSETUP_WSL_CONF="$TEST_ROOT/missing.conf" wsl_drive_root)" = /mnt/ ] || fail 'missing wsl.conf did not default to /mnt/'
check_root /windows/ '[automount]\nroot = /windows/\n'
check_root /x/ '[AutoMount]\n  Root=/x\n'
check_root / '[automount]\nenabled = true\nroot = "/"  # drives at /c\n'
check_root /mnt/ '[network]\nroot = /elsewhere/\n'
check_root /mnt/ '[automount]\nroot = relative/\n'
check_root /first/ '[automount]\nroot = /first/\nroot = /second/\n'
# Forms a Windows editor or a hand edit can produce.
check_root /win/ '\0357\0273\0277[automount]\nroot = /win/\n'
check_root /win/ '[automount]  # drives\nroot = /win/\n'
check_root /win/ "[automount]\nroot = '/win/'\n"
check_root /win/ '[automount]\r\nroot = "/win/"\r\n'
check_root /mnt/ '[network]  # x\nroot = /win/\n'
DEVSETUP_WSL_CONF="$TEST_ROOT/missing.conf" wsl_is_windows_path /mnt/c/Users || fail '/mnt/c not recognized as a Windows drive'
DEVSETUP_WSL_CONF="$TEST_ROOT/missing.conf" wsl_is_windows_path /mnt/d || fail '/mnt/d not recognized as a Windows drive'
if DEVSETUP_WSL_CONF="$TEST_ROOT/missing.conf" wsl_is_windows_path /mnt/wsl/shared; then fail '/mnt/wsl mistaken for a Windows drive'; fi
if DEVSETUP_WSL_CONF="$TEST_ROOT/missing.conf" wsl_is_windows_path /home/me/src; then fail 'Linux path mistaken for a Windows drive'; fi
# A moved root adds a guarded location; the default /mnt/ drives stay guarded too, so a
# wsl.conf read differently from WSL never removes the default protection.
printf '[automount]\nroot = /win/\n' > "$TEST_ROOT/moved.conf"
DEVSETUP_WSL_CONF="$TEST_ROOT/moved.conf" wsl_is_windows_path /win/d/src || fail 'drive under the moved root not recognized'
DEVSETUP_WSL_CONF="$TEST_ROOT/moved.conf" wsl_is_windows_path /mnt/c/src || fail '/mnt/c no longer guarded after the root moved'
if DEVSETUP_WSL_CONF="$TEST_ROOT/moved.conf" wsl_is_windows_path /win/data/src; then fail 'non-drive directory under the moved root mistaken for a drive'; fi
# A configured root reached through a symlink still matches resolved paths, as on
# macOS where the temporary directory itself is a symlink.
# Git Bash may copy instead of linking; then the case is skipped and the copy removed.
mkdir -p "$TEST_ROOT/real-root/c/x"
if ln -s "$TEST_ROOT/real-root" "$TEST_ROOT/link-root" 2>/dev/null && [ -L "$TEST_ROOT/link-root" ]; then
  printf '[automount]\nroot = %s/\n' "$TEST_ROOT/link-root" > "$TEST_ROOT/link-root.conf"
  real_drive=$(cd -P -- "$TEST_ROOT/real-root/c/x" && pwd -P)
  DEVSETUP_WSL_CONF="$TEST_ROOT/link-root.conf" wsl_is_windows_path "$real_drive" || fail 'resolved drive path not matched through a symlinked root'
else
  rm -rf -- "$TEST_ROOT/link-root"
  echo 'SKIP: host cannot create a real symbolic link; symlinked mount root not exercised'
fi
pass 'WSL drive mount root is read from wsl.conf and drives are recognized precisely'
mkdir -p "$TEST_ROOT/system-bin" "$TEST_ROOT/local-bin" "$TEST_ROOT/new-profile"
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/system-bin/xdg-open"
chmod +x "$TEST_ROOT/system-bin/xdg-open"
PATH="$TEST_ROOT/local-bin:$TEST_ROOT/system-bin:$PATH" install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/local-bin" "$TEST_ROOT/new-profile"
[ ! -e "$TEST_ROOT/local-bin/xdg-open" ] || fail 'system xdg-open was shadowed'
cp "$TEST_ROOT/system-bin/xdg-open" "$TEST_ROOT/system-bin/wslview"
mkdir -p "$TEST_ROOT/other-bin" "$TEST_ROOT/other-profile"
if PATH="$TEST_ROOT/other-bin:$TEST_ROOT/system-bin:$PATH" install_browser_bridge "$ROOT/helpers/wslview.sh" "$TEST_ROOT/other-bin" "$TEST_ROOT/other-profile"; then fail 'system wslview was shadowed'; fi
[ ! -e "$TEST_ROOT/other-bin/wslview" ] && [ ! -e "$TEST_ROOT/other-profile/wsl-browser.sh" ] || fail 'handler preservation performed writes'
pass 'Bridge preserves handlers in other PATH directories before writing'
unset -f sudo

# Full bootstrap fixtures: every external provisioning/auth command is mocked, and
# the platform is described by fixture files rather than read from this machine.
mkdir -p "$TEST_ROOT/mock-bin" "$TEST_ROOT/user" "$TEST_ROOT/os"
# A narrow utility PATH prevents missing mocks from falling through to real tools
# such as uv or rustup installed on the test host. Wrappers also work in Git Bash.
# sh must be present: without it a downloaded installer could never run, and the
# test that partial downloads are never executed would pass vacuously.
mkdir -p "$TEST_ROOT/utilities"
for utility in bash sh awk cat chmod cmp cp dirname env grep head ls mkdir mktemp mv rm sed tr uname touch; do
  utility_path=$(command -v "$utility") || fail "test dependency unavailable: $utility"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$utility_path" > "$TEST_ROOT/utilities/$utility"
  chmod +x "$TEST_ROOT/utilities/$utility"
done
printf 'ID=fedora\nPRETTY_NAME="Fedora Linux 44"\n' > "$TEST_ROOT/os/fedora"
printf 'ID=ubuntu\nID_LIKE=debian\nPRETTY_NAME="Ubuntu 24.04 LTS"\n' > "$TEST_ROOT/os/ubuntu"
printf 'ID=arch\nPRETTY_NAME="Arch Linux"\n' > "$TEST_ROOT/os/arch"
printf 'ID=rocky\nID_LIKE="rhel centos fedora"\n' > "$TEST_ROOT/os/rocky"
printf 'Linux version 6.8.0-generic (buildd@ubuntu) #1 SMP\n' > "$TEST_ROOT/os/native"
printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 #1 SMP\n' > "$TEST_ROOT/os/wsl"
export TEST_EVENTS="$TEST_ROOT/events" TEST_EXTENSIONS="$TEST_ROOT/extensions"
: > "$TEST_EVENTS"; : > "$TEST_EXTENSIONS"
cat > "$TEST_ROOT/mock-bin/mock" <<'MOCK'
#!/usr/bin/env bash
name=${0##*/}
printf '%s\n' "$name $*" >> "$TEST_EVENTS"
if [ "${TEST_RUST_PROBE:-0}" = 1 ]; then
  case "$name" in
    rustup|rustc) [ "${RUSTUP_AUTO_INSTALL:-1}" = 0 ] || touch "$TEST_EVENTS.auto-installed" ;;
    gh) [ "${RUSTUP_AUTO_INSTALL-unset}" = "$TEST_ORIGINAL_AUTO_INSTALL" ] || exit 91 ;;
  esac
fi
if [ "${TEST_OLD_RUSTUP:-0}" = 1 ]; then
  case "$name" in
    rustup|rustc)
      # rustup before 1.28 ignores RUSTUP_AUTO_INSTALL and installs a toolchain
      # pinned by the working directory or any parent.
      dir=$PWD
      while :; do
        if [ -f "$dir/rust-toolchain.toml" ]; then touch "$TEST_EVENTS.auto-installed"; break; fi
        [ "$dir" != / ] || break
        dir=$(dirname "$dir")
      done ;;
  esac
fi
missing() { case " ${TEST_MISSING_PKGS:-} " in *" $1 "*) return 0;; esac; return 1; }
case "$name" in
  sudo)
    [ "${TEST_ALLOW_SUDO:-0}" = 1 ] || { echo 'Unexpected privileged command in bootstrap test' >&2; exit 90; }
    exec "$@" ;;
  dnf|apt-get)
    [ "${TEST_ALLOW_SUDO:-0}" = 1 ] || { echo 'Unexpected package manager call' >&2; exit 90; }
    if [ "${TEST_GH_UNAVAILABLE:-0}" = 1 ]; then
      for package in "$@"; do [ "$package" != gh ] || exit 1; done
    fi
    # A background update holding the dpkg lock, as on a freshly installed Ubuntu.
    if [ "${TEST_PKG_LOCKED:-0}" = 1 ] && [ "$1" = install ]; then
      echo 'E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 412 (unattended-upgr)' >&2
      exit 100
    fi
    if [ "$1" = install ] && [ -n "${TEST_AWK_SOURCE:-}" ]; then
      for package in "$@"; do
        if [ "$package" = gawk ]; then cp "$TEST_AWK_SOURCE" "${TEST_EVENTS%/*}/utilities/awk"; fi
      done
    fi ;;
  rpm)
    if [ "$2" = --whatprovides ]; then
      [ "$3" = pkg-config ] && [ "${TEST_PKG_CONFIG_PROVIDER:-0}" = 1 ] || exit 1
    elif missing "$2"; then exit 1; fi ;;
  dpkg-query) for last; do :; done; if missing "$last"; then exit 1; fi; printf 'install ok installed' ;;
  brew)
    case "$1" in
      list) if missing "${3:-}"; then exit 1; fi ;;
      shellenv) printf 'export PATH="%s:$PATH"\n' "${0%/*}" ;;
      install)
        # A successful cask install provides the 'code' command, as the real cask does.
        if [ "${2:-}" = --cask ]; then cp "$0" "${0%/*}/code"; fi ;;
    esac ;;
  sw_vers) printf '15.0\n' ;;
  xcode-select) [ "${TEST_NO_CLT:-0}" = 1 ] && exit 2; printf '/Library/Developer/CommandLineTools\n' ;;
  rustup)
    if [ "$*" = 'component list --installed' ]; then
      [ "${TEST_COMPONENT_QUERY_FAIL:-0}" != 1 ] || exit 44
      for component in rustfmt clippy; do
        case " ${TEST_MISSING_COMPONENTS:-} " in *" $component "*) ;; *) printf '%s-x86_64-unknown-linux-gnu\n' "$component" ;; esac
      done
    else printf 'rustup fixture\n'; fi ;;
  rustc) [ "${TEST_BROKEN_RUSTC:-0}" != 1 ] || exit 42; printf 'rustc 1.85.0\n' ;;
  uv) [ "${TEST_BROKEN_UV:-0}" != 1 ] || exit 43; printf 'uv 0.9.0\n' ;;
  code)
    if [ "${TEST_CODE_MUTATES:-0}" = 1 ]; then touch "$TEST_EVENTS.server-started"; exit 99; fi
    if [ "$1" = --list-extensions ] && [ "${TEST_CODE_LIST_FAIL:-0}" = 1 ]; then exit 9; fi
    if [ "$1" = --list-extensions ]; then cat "$TEST_EXTENSIONS"
    else printf '%s\n' "$2" >> "$TEST_EXTENSIONS"; fi ;;
  gh)
    version=${TEST_GH_VERSION:-2.45.0}
    if [ "$1" = --version ]; then printf 'gh version %s (2026-01-01)\n' "$version"; exit 0; fi
    if [ "$2" = token ]; then echo 'unexpected token lookup' >&2; exit 99; fi
    # Builds before 2.40 reject --active, as the real CLI does.
    case "$version $*" in 2.[0-3][0-9].*--active*) echo 'unknown flag: --active' >&2; exit 1;; esac
    if [ "${3:-}" = --help ]; then
      case "$version" in 2.[0-3][0-9].*) :;; *) printf '  --active\n';; esac
    elif [ "${TEST_SCOPES:-present}" = missing ]; then
      printf "Logged in to github.com account workflow\n  - Token scopes: 'repo'\n"
      case " $* " in *' --active '*) :;; *) printf "  - Token scopes: 'workflow'\n";; esac
    elif [ "${TEST_SCOPES:-present}" != unknown ]; then
      printf "  - Token scopes: 'repo', 'workflow'\n"
    fi ;;
  claude)
    if [ "${TEST_MCP_LOOKALIKE:-0}" = 1 ] && [ "${2:-}" = get ]; then exit 1; fi
    printf 'context7 github-backup https://github.com/other/server\n' ;;
  git)
    # Only identity lookups answer; other git calls behave as before.
    if [ "${1:-} ${2:-} ${3:-}" = 'config --global --get' ]; then
      case "${4:-}" in user.name) value=${TEST_GIT_NAME:-} ;; user.email) value=${TEST_GIT_EMAIL:-} ;; *) value= ;; esac
      [ -n "$value" ] || exit 1
      printf '%s\n' "$value"
    fi ;;
  curl)
    # A partial downloaded script must never be executed after curl fails.
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then shift; printf 'touch "%s"\n' "$TEST_EVENTS.executed" > "$1"; break; fi
      shift
    done
    exit 22 ;;
  codex) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
for command in sudo dnf apt-get rpm dpkg-query brew sw_vers xcode-select rustup rustc cargo uv code gh claude codex git curl cargo-binstall cargo-nextest cargo-audit cargo-machete cargo-deny bacon typos; do
  cp "$TEST_ROOT/mock-bin/mock" "$TEST_ROOT/mock-bin/$command"
  chmod +x "$TEST_ROOT/mock-bin/$command"
done
# run_bootstrap OS KERNEL [options]: HOME and PATH are set only for the child.
run_bootstrap() {
  local os="$1" kernel="$2"; shift 2
  # The kernel is pinned too, so Linux cases behave the same on a macOS test runner.
  env HOME="$TEST_ROOT/user" PATH="$TEST_ROOT/mock-bin:$TEST_ROOT/utilities" \
    DEVSETUP_OS_RELEASE="$TEST_ROOT/os/$os" DEVSETUP_PROC_VERSION="$TEST_ROOT/os/$kernel" \
    DEVSETUP_KERNEL="${TEST_KERNEL:-Linux}" DEVSETUP_BREW_CANDIDATES="${TEST_BREW_CANDIDATES:-$TEST_ROOT/no-such-brew}" \
    DEVSETUP_WSL_CONF="${TEST_WSL_CONF:-$TEST_ROOT/no-wsl.conf}" DEVSETUP_WSL_POWERSHELL="$TEST_ROOT/no-powershell.exe" \
    CODEX_HOME="${TEST_CODEX_HOME:-}" \
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

# The WSL code shim can provision a server even for --list-extensions.
for mode in --check --doctor; do
  : > "$TEST_EVENTS"
  TEST_CODE_MUTATES=1 run_bootstrap fedora wsl "$mode" --stack=rust > "$TEST_ROOT/wsl-editor.log"
  [ ! -e "$TEST_EVENTS.server-started" ] || fail 'WSL read-only mode initialized the editor server'
  if grep -q '^code ' "$TEST_EVENTS"; then fail 'WSL read-only mode invoked code'; fi
  grep -q 'WSL extensions not queried' "$TEST_ROOT/wsl-editor.log" || fail 'WSL editor limitation was hidden'
done
pass 'WSL check and doctor never initialize the editor, including the Rust probe'

baseline=0
run_bootstrap fedora native --check > "$TEST_ROOT/with-awk.log" || baseline=$?
mv "$TEST_ROOT/utilities/awk" "$TEST_ROOT/awk.saved"
result=0
TEST_MISSING_PKGS=gawk run_bootstrap fedora native --check > "$TEST_ROOT/no-awk.log" || result=$?
grep -q 'FAIL.*gawk is missing' "$TEST_ROOT/no-awk.log" || fail 'missing awk passed readiness'
grep -q 'awk unavailable until gawk is installed' "$TEST_ROOT/no-awk.log" || fail 'awk consequence not explained'
[ "$result" -eq $((baseline + 1)) ] || fail "missing awk counted $((result - baseline)) failures instead of one"
result=0
TEST_MISSING_PKGS=gawk run_bootstrap fedora native --no-sudo > "$TEST_ROOT/no-awk-nosudo.log" || result=$?
[ "$(grep -c 'FAIL.*awk' "$TEST_ROOT/no-awk-nosudo.log")" -eq 1 ] || fail 'missing awk counted twice without sudo'
result=0
env HOME="$TEST_ROOT/user" PATH="$TEST_ROOT/mock-bin:$TEST_ROOT/utilities" \
  DEVSETUP_KERNEL=Linux DEVSETUP_PROC_VERSION="$TEST_ROOT/os/native" \
  bash "$ROOT/new-project.sh" --name no-awk --environment linux --parent "$TEST_ROOT/no-awk-parent" \
  > "$TEST_ROOT/no-awk-scaffold.log" 2>&1 || result=$?
[ "$result" -ne 0 ] && grep -q 'awk is required' "$TEST_ROOT/no-awk-scaffold.log" || fail 'scaffolder did not preflight awk'
[ ! -e "$TEST_ROOT/no-awk-parent" ] || fail 'scaffolder staged files before checking awk'
for os in fedora ubuntu; do
  : > "$TEST_EVENTS"
  TEST_ALLOW_SUDO=1 TEST_MISSING_PKGS=gawk TEST_AWK_SOURCE="$TEST_ROOT/awk.saved" \
    run_bootstrap "$os" native > "$TEST_ROOT/awk-install.log"
  grep -Eq '^(dnf|apt-get) install -y .*gawk' "$TEST_EVENTS" || fail 'missing awk package not installed'
  [ -x "$TEST_ROOT/utilities/awk" ] || fail 'awk unavailable after package installation'
  rm "$TEST_ROOT/utilities/awk"
done
mv "$TEST_ROOT/awk.saved" "$TEST_ROOT/utilities/awk"
pass 'Minimal Linux installs awk, counts a missing awk once, and scaffolding fails before writes without it'

mv "$TEST_ROOT/mock-bin/uv" "$TEST_ROOT/uv.saved"
for mode in --check --doctor; do
  result=0
  run_bootstrap fedora native "$mode" --stack=python > "$TEST_ROOT/no-uv.log" || result=$?
  [ "$result" -ne 0 ] && grep -q 'uv not installed' "$TEST_ROOT/no-uv.log" || fail 'missing selected Python runtime passed readiness'
done
mv "$TEST_ROOT/uv.saved" "$TEST_ROOT/mock-bin/uv"
for mode in --check --doctor; do
  result=0
  TEST_BROKEN_RUSTC=1 run_bootstrap fedora native "$mode" --stack=rust > "$TEST_ROOT/broken-rust.log" || result=$?
  [ "$result" -ne 0 ] && grep -q 'rustc --version failed' "$TEST_ROOT/broken-rust.log" || fail 'broken compiler passed readiness'
  result=0
  TEST_BROKEN_UV=1 run_bootstrap fedora native "$mode" --stack=python > "$TEST_ROOT/broken-uv.log" || result=$?
  [ "$result" -ne 0 ] && grep -q 'uv --version failed' "$TEST_ROOT/broken-uv.log" || fail 'broken uv passed readiness'
done
pass 'Selected runtimes must exist and pass version probes in check and doctor modes'
for mode in --check --doctor; do
  for missing in rustfmt clippy 'rustfmt clippy'; do
    : > "$TEST_EVENTS"
    result=0
    TEST_MISSING_COMPONENTS="$missing" run_bootstrap fedora native "$mode" --stack=rust > "$TEST_ROOT/components.log" 2>&1 || result=$?
    expected=1; [ "$missing" != 'rustfmt clippy' ] || expected=2
    [ "$result" -eq "$expected" ] || fail 'missing components were not counted exactly once'
    for component in $missing; do
      grep -q "FAIL.*$component missing" "$TEST_ROOT/components.log" || fail 'missing component not named'
    done
    if grep -Eq 'rustup component add|^(sudo|dnf|cargo) ' "$TEST_EVENTS"; then fail 'component check provisioned tools'; fi
  done
  result=0
  TEST_COMPONENT_QUERY_FAIL=1 run_bootstrap fedora native "$mode" --stack=rust > "$TEST_ROOT/component-query.log" 2>&1 || result=$?
  [ "$result" -eq 1 ] && grep -q 'could not query installed Rust components' "$TEST_ROOT/component-query.log" || fail 'component query failure was not reported once'
  result=0
  TEST_BROKEN_RUSTC=1 TEST_COMPONENT_QUERY_FAIL=1 run_bootstrap fedora native "$mode" --stack=rust > "$TEST_ROOT/component-toolchain.log" 2>&1 || result=$?
  [ "$result" -eq 1 ] || fail 'broken toolchain counted component consequences'
done
pass 'Rust readiness requires rustfmt and clippy without provisioning or duplicate failures'

mkdir -p "$TEST_ROOT/pinned-project"
printf '[toolchain]\nchannel = "1.85.0"\n' > "$TEST_ROOT/pinned-project/rust-toolchain.toml"
for initial in unset 0 1; do
  for mode in --check --doctor; do
    result=0
    (
      if [ "$initial" = unset ]; then unset RUSTUP_AUTO_INSTALL; else export RUSTUP_AUTO_INSTALL="$initial"; fi
      export TEST_ORIGINAL_AUTO_INSTALL="$initial" TEST_RUST_PROBE=1 TEST_BROKEN_RUSTC=1
      cd "$TEST_ROOT/pinned-project"
      run_bootstrap fedora native "$mode" --stack=rust
    ) > "$TEST_ROOT/rust-probe.log" || result=$?
    [ "$result" -ne 0 ] && grep -q 'rustc --version failed' "$TEST_ROOT/rust-probe.log" || fail 'absent pinned toolchain did not fail'
    [ ! -e "$TEST_EVENTS.auto-installed" ] || fail 'read-only Rust probe enabled automatic installation'
    grep -q 'GitHub CLI is authenticated' "$TEST_ROOT/rust-probe.log" || fail 'Rust probe changed environment for later commands'
  done
done
mkdir -p "$TEST_ROOT/pinned-project/src"
for mode in --check --doctor; do
  rm -f "$TEST_EVENTS.auto-installed"
  (
    export TEST_OLD_RUSTUP=1
    cd "$TEST_ROOT/pinned-project/src"
    run_bootstrap fedora native "$mode" --stack=rust || :
  ) > "$TEST_ROOT/old-rustup.log"
  [ ! -e "$TEST_EVENTS.auto-installed" ] || fail "old rustup installed a project-pinned toolchain in $mode"
  grep -q 'rustc 1.85.0' "$TEST_ROOT/old-rustup.log" || fail "machine Rust toolchain not probed in $mode"
done
pass 'Rust checks suppress automatic toolchain installation and preserve caller settings'


: > "$TEST_EVENTS"
run_bootstrap fedora wsl --no-sudo --stack=rust --configure-agents > "$TEST_ROOT/first.log"
grep -q '^rustup component add' "$TEST_EVENTS" || fail 'Rust selection skipped components'
grep -q 'rust-analyzer' "$TEST_EVENTS" || fail 'Rust selection skipped extensions'
cp "$TEST_ROOT/user/.codex/config.toml" "$TEST_ROOT/config.before"
cp "$TEST_ROOT/user/.claude/settings.json" "$TEST_ROOT/settings.before"
for rule in 'Read(**/.env)' 'Read(**/.env.*)' 'Read(**/*.pem)' 'Read(**/*.key)'; do
  grep -qF "\"$rule\"" "$TEST_ROOT/user/.claude/settings.json" || fail "Claude settings lack $rule"
done
run_bootstrap fedora wsl --no-sudo --stack=rust --configure-agents > "$TEST_ROOT/second.log"
cmp -s "$TEST_ROOT/config.before" "$TEST_ROOT/user/.codex/config.toml" || fail 'Codex config changed on rerun'
cmp -s "$TEST_ROOT/settings.before" "$TEST_ROOT/user/.claude/settings.json" || fail 'Claude config changed on rerun'
if grep -Eq 'mcp_servers\.github|GITHUB_MCP_PAT' "$TEST_ROOT/user/.codex/config.toml"; then fail 'new config enabled GitHub MCP credential inheritance'; fi
if grep -Eq '^(sudo|dnf|apt-get) ' "$TEST_EVENTS"; then fail '--no-sudo invoked privilege escalation'; fi
pass 'First run and rerun preserve configuration and honor --no-sudo'
printf '# [mcp_servers.github] is only a comment\n' > "$TEST_ROOT/user/.codex/config.toml"
cp "$TEST_ROOT/user/.codex/config.toml" "$TEST_ROOT/existing-toml"
run_bootstrap fedora native --configure-agents > /dev/null
cmp -s "$TEST_ROOT/existing-toml" "$TEST_ROOT/user/.codex/config.toml" || fail 'existing TOML was modified'
cp "$TEST_ROOT/config.before" "$TEST_ROOT/user/.codex/config.toml"
pass 'Existing TOML is preserved without guessing table structure'
: > "$TEST_EVENTS"
result=0
TEST_CODE_LIST_FAIL=1 run_bootstrap fedora native > "$TEST_ROOT/extensions-failed.log" || result=$?
[ "$result" -ne 0 ] && ! grep -q '^code --install-extension' "$TEST_EVENTS" || fail 'failed extension listing did not stop installs'
pass 'Failed extension listing stops dependent installation'
printf 'timonwongXshellcheck\n' > "$TEST_EXTENSIONS"
: > "$TEST_EVENTS"
run_bootstrap fedora native > /dev/null
grep -q '^code --install-extension timonwong.shellcheck' "$TEST_EVENTS" || fail 'extension IDs matched as regular expressions'
pass 'Extension IDs are matched literally'
: > "$TEST_EVENTS"
run_bootstrap fedora wsl --doctor --stack=rust --configure-agents > "$TEST_ROOT/doctor.log"
cmp -s "$TEST_ROOT/config.before" "$TEST_ROOT/user/.codex/config.toml" || fail 'Doctor changed config'
if grep -Eq '^(sudo|dnf|apt-get|curl) |^cargo (install|binstall)|^code --install|^claude mcp add|^gh auth setup-git' "$TEST_EVENTS"; then fail 'Doctor invoked mutation'; fi
grep -q 'src does not exist yet' "$TEST_ROOT/doctor.log" || fail 'WSL doctor did not report project location'
grep -q 'Git commit name or email is not set' "$TEST_ROOT/doctor.log" || fail 'doctor did not report a missing Git identity'
if grep -Eq '^git config --global user\.' "$TEST_EVENTS"; then fail 'doctor wrote Git identity'; fi
pass 'Doctor performs no provisioning or configuration writes'
# Earlier runs already wrote agent configuration, so prove check and doctor create
# none on a home that has none yet.
mv "$TEST_ROOT/user/.codex" "$TEST_ROOT/codex.aside"; mv "$TEST_ROOT/user/.claude" "$TEST_ROOT/claude.aside"
for mode in --check --doctor; do
  run_bootstrap fedora native "$mode" --configure-agents > /dev/null 2>&1 || true
  [ ! -e "$TEST_ROOT/user/.codex" ] && [ ! -e "$TEST_ROOT/user/.claude" ] || fail "$mode created agent configuration"
done
mv "$TEST_ROOT/codex.aside" "$TEST_ROOT/user/.codex"; mv "$TEST_ROOT/claude.aside" "$TEST_ROOT/user/.claude"
pass 'Check and doctor create no agent configuration on a fresh home'
# Read-only modes must not run shell code from the user's home, even rustup's env file.
mkdir -p "$TEST_ROOT/user/.cargo"
printf 'touch "%s"\n' "$TEST_ROOT/cargo-env-ran" > "$TEST_ROOT/user/.cargo/env"
run_bootstrap fedora native --no-sudo --check --stack=rust > /dev/null 2>&1 || true
run_bootstrap fedora native --no-sudo --doctor --stack=rust > /dev/null 2>&1 || true
[ ! -e "$TEST_ROOT/cargo-env-ran" ] || fail 'check or doctor mode ran ~/.cargo/env'
rm -rf -- "$TEST_ROOT/user/.cargo"
pass 'Check and doctor modes never run ~/.cargo/env'
TEST_GIT_NAME=fixture TEST_GIT_EMAIL=1+Fixture@Users.Noreply.GitHub.com run_bootstrap ubuntu native --doctor > "$TEST_ROOT/doctor-id.log"
grep -q 'Git commit name and email are set (GitHub private address)' "$TEST_ROOT/doctor-id.log" || fail 'GitHub private address not recognised'
if grep -q 'Noreply' "$TEST_ROOT/doctor-id.log"; then fail 'doctor printed the commit email'; fi
TEST_GIT_NAME=fixture TEST_GIT_EMAIL=someone@example.invalid run_bootstrap ubuntu native --doctor > "$TEST_ROOT/doctor-public.log"
grep -q 'not a GitHub private (noreply) address' "$TEST_ROOT/doctor-public.log" || fail 'public commit email not reported'
if grep -q 'example.invalid' "$TEST_ROOT/doctor-public.log"; then fail 'doctor printed the commit email'; fi
TEST_GIT_NAME=fixture run_bootstrap ubuntu native --doctor > "$TEST_ROOT/doctor-noemail.log"
grep -q 'Git commit name or email is not set' "$TEST_ROOT/doctor-noemail.log" || fail 'missing commit email not reported'
pass 'Doctor reports whether the Git identity is set without printing it'
if run_bootstrap fedora wsl --no-sudo --install-browser-bridge > "$TEST_ROOT/conflict.log" 2>&1; then fail 'conflicting options accepted'; fi
pass 'Conflicting privilege options fail before provisioning'
# A wslview elsewhere on PATH (for example from wslu) is preserved and is not a failure.
cp "$TEST_ROOT/mock-bin/mock" "$TEST_ROOT/mock-bin/wslview"
chmod +x "$TEST_ROOT/mock-bin/wslview"
for mode in --check --install-browser-bridge; do
  : > "$TEST_EVENTS"
  result=0
  run_bootstrap fedora wsl "$mode" > "$TEST_ROOT/existing-bridge.log" 2>&1 || result=$?
  [ "$result" -eq 0 ] && grep -q 'existing browser bridge left unchanged' "$TEST_ROOT/existing-bridge.log" \
    || fail "existing wslview reported as a failure ($mode)"
  grep -Fq "export BROWSER=$TEST_ROOT/mock-bin/wslview" "$TEST_ROOT/existing-bridge.log" || fail "BROWSER hint missing ($mode)"
  if grep -Eq '^(sudo|wslview) ' "$TEST_EVENTS"; then fail "existing wslview was replaced or launched ($mode)"; fi
done
rm -f -- "$TEST_ROOT/mock-bin/wslview"
pass 'An existing wslview on PATH is reported as working and left unchanged'
# Installation looks for powershell.exe the same way the bridge does. Privileged
# writes stay blocked by the sudo mock, so the run stops at installation.
result=0
run_bootstrap fedora wsl --install-browser-bridge > "$TEST_ROOT/no-ps-bridge.log" 2>&1 || result=$?
[ "$result" -ne 0 ] && grep -q 'powershell.exe not reachable' "$TEST_ROOT/no-ps-bridge.log" || fail 'missing powershell.exe not reported before installation'
cp "$TEST_ROOT/mock-bin/mock" "$TEST_ROOT/mock-bin/powershell.exe"
chmod +x "$TEST_ROOT/mock-bin/powershell.exe"
run_bootstrap fedora wsl --install-browser-bridge > "$TEST_ROOT/path-ps-bridge.log" 2>&1 || true
if grep -q 'powershell.exe not reachable' "$TEST_ROOT/path-ps-bridge.log"; then fail 'powershell.exe on PATH was not found'; fi
grep -q 'browser bridge installation failed' "$TEST_ROOT/path-ps-bridge.log" || fail 'installation was not attempted with powershell.exe on PATH'
rm -f -- "$TEST_ROOT/mock-bin/powershell.exe"
pass 'Bridge installation finds powershell.exe on PATH'
# The doctor's project-location check follows a drive mount root moved by wsl.conf.
mkdir -p "$TEST_ROOT/doctor-win/c/projects"
printf '[automount]\nroot = %s/\n' "$TEST_ROOT/doctor-win" > "$TEST_ROOT/doctor-wsl.conf"
if ln -s "$TEST_ROOT/doctor-win/c/projects" "$TEST_ROOT/user/src" 2>/dev/null && [ -L "$TEST_ROOT/user/src" ]; then
  TEST_WSL_CONF="$TEST_ROOT/doctor-wsl.conf" run_bootstrap fedora wsl --doctor > "$TEST_ROOT/doctor-moved.log" || true
  grep -q 'on the Windows filesystem' "$TEST_ROOT/doctor-moved.log" || fail 'doctor missed a project folder on a moved Windows drive'
  rm -f -- "$TEST_ROOT/user/src"
  pass 'Doctor follows the configured drive mount root'
else
  # Git Bash may copy instead of linking; remove the copy so later cases start clean.
  rm -rf -- "$TEST_ROOT/user/src"
  echo 'SKIP: host cannot create a real symbolic link; moved-root doctor case not exercised'
fi

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

# Fedora installs pkgconf-pkg-config as the provider of the pkg-config capability.
: > "$TEST_EVENTS"
TEST_MISSING_PKGS=pkg-config TEST_PKG_CONFIG_PROVIDER=1 run_bootstrap fedora native --stack=rust --check > "$TEST_ROOT/rpm-provider.log"
grep -q '^rpm -q --whatprovides pkg-config$' "$TEST_EVENTS" || fail 'RPM provider was not checked'
if grep -Eq '^(sudo|dnf) ' "$TEST_EVENTS"; then fail 'provider check attempted provisioning'; fi
pass 'Fedora check accepts an installed pkg-config provider'
result=0
TEST_MISSING_PKGS=pkg-config run_bootstrap fedora native --stack=rust --check > "$TEST_ROOT/rpm-no-provider.log" 2>&1 || result=$?
[ "$result" -ne 0 ] || fail 'missing RPM capability incorrectly passed check'
grep -q 'pkg-config' "$TEST_ROOT/rpm-no-provider.log" || fail 'missing RPM capability was not reported'
pass 'Fedora check rejects a package with no installed provider'

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
: > "$TEST_EVENTS"
result=0
TEST_ALLOW_SUDO=1 TEST_MISSING_PKGS='curl git gh' TEST_GH_UNAVAILABLE=1 run_bootstrap rocky native > "$TEST_ROOT/rpm-unavailable.log" 2>&1 || result=$?
[ "$result" -ne 0 ] && grep -qx 'dnf install -y curl git' "$TEST_EVENTS" && grep -qx 'dnf install -y gh' "$TEST_EVENTS" || fail 'unavailable gh blocked base RPM packages'
grep -q 'official RPM repository' "$TEST_ROOT/rpm-unavailable.log" || fail 'missing gh repository guidance'
pass 'Unavailable gh is isolated from base RPM packages and still returns failure'
mv "$TEST_ROOT/mock-bin/dnf" "$TEST_ROOT/dnf.saved"
: > "$TEST_EVENTS"
run_bootstrap rocky native --check > "$TEST_ROOT/no-dnf.log"
grep -q 'dnf is unavailable' "$TEST_ROOT/no-dnf.log" || fail 'missing package manager not diagnosed'
if grep -Eq '^(sudo|dnf|rpm) ' "$TEST_EVENTS"; then fail 'missing dnf still invoked RPM provisioning'; fi
mv "$TEST_ROOT/dnf.saved" "$TEST_ROOT/mock-bin/dnf"
pass 'RHEL-family systems without dnf fall back to command checks'
result=0
TEST_ALLOW_SUDO=1 TEST_MISSING_PKGS=gh TEST_PKG_LOCKED=1 run_bootstrap ubuntu native > "$TEST_ROOT/locked.log" 2>&1 || result=$?
[ "$result" -ne 0 ] || fail 'failed package installation returned success'
grep -q 'package installation failed' "$TEST_ROOT/locked.log" && grep -q 'wait for it to' "$TEST_ROOT/locked.log" \
  && grep -q 'never delete lock files' "$TEST_ROOT/locked.log" || fail 'package lock failure not explained'
if grep -q 'rerun with --no-sudo to continue' "$TEST_ROOT/locked.log"; then fail 'package failure still points to --no-sudo first'; fi
pass 'A failed package installation explains lock waits and fails'
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
grep -q 'lacks --active' "$TEST_ROOT/oldgh.log" || fail 'old gh not diagnosed'
grep -q 'GitHub CLI is authenticated' "$TEST_ROOT/oldgh.log" || fail 'old gh authentication misreported'
pass 'GitHub CLI older than 2.40 is diagnosed and still recognized as authenticated'
TEST_SCOPES=missing run_bootstrap ubuntu native --check > "$TEST_ROOT/scopes.log"
grep -q "active classic token lacks" "$TEST_ROOT/scopes.log" || fail 'account name or inactive scopes produced false success'
TEST_SCOPES=unknown run_bootstrap ubuntu native --check > "$TEST_ROOT/scopes.log"
grep -q 'permission could not be determined' "$TEST_ROOT/scopes.log" || fail 'fine-grained or unknown scope reported missing'
printf 'export GITHUB_MCP_PAT=fake-profile-secret\n' > "$TEST_ROOT/user/.zshrc"
run_bootstrap ubuntu native --check > "$TEST_ROOT/profiles.log"
grep -Fq '.zshrc' "$TEST_ROOT/profiles.log" && ! grep -q fake-profile-secret "$TEST_ROOT/profiles.log" || fail 'zsh legacy warning missing or leaked value'
codex_config="$TEST_ROOT/user/.codex/config.toml"
cp "$codex_config" "$TEST_ROOT/codex-config.saved"
for case in \
  'warn|[mcp_servers.github]\nurl = "https://example.invalid/mcp"\nbearer_token_env_var = "GITHUB_MCP_PAT"\n' \
  "warn|mcp_servers.github = { bearer_token_env_var = 'GITHUB_MCP_PAT' }\n" \
  'quiet|[mcp_servers.github]\n# bearer_token_env_var = "GITHUB_MCP_PAT"\n' \
  'quiet|[mcp_servers.github]\nbearer_token_env_var = "CUSTOM_GITHUB_TOKEN"\n'; do
  # shellcheck disable=SC2059 # The fixture's \n escapes are intended.
  printf "${case#*|}" > "$codex_config"
  cp "$codex_config" "$TEST_ROOT/codex-config.before"
  run_bootstrap ubuntu native --check > "$TEST_ROOT/codex-legacy.log" || true
  cmp -s "$codex_config" "$TEST_ROOT/codex-config.before" || fail 'legacy Codex check modified the configuration'
  if grep -q 'Legacy Codex GitHub MCP entry' "$TEST_ROOT/codex-legacy.log"; then found=warn; else found=quiet; fi
  [ "$found" = "${case%%|*}" ] || fail "legacy Codex entry check expected ${case%%|*}, got $found: ${case#*|}"
done
cp "$TEST_ROOT/codex-config.saved" "$codex_config"
# Codex reads CODEX_HOME when set; the bootstrap writes, warns and diagnoses there.
custom_codex="$TEST_ROOT/custom codex home"
mkdir -p "$custom_codex"
TEST_CODEX_HOME="$custom_codex" run_bootstrap ubuntu native --configure-agents > "$TEST_ROOT/codex-home.log"
[ -f "$custom_codex/config.toml" ] && grep -q 'approval_policy' "$custom_codex/config.toml" || fail 'Codex defaults not written to CODEX_HOME'
cmp -s "$TEST_ROOT/codex-config.saved" "$codex_config" || fail 'CODEX_HOME run changed ~/.codex/config.toml'
TEST_CODEX_HOME="$custom_codex" run_bootstrap ubuntu native --doctor --configure-agents > "$TEST_ROOT/codex-home.log" || true
grep -q 'Codex user configuration exists' "$TEST_ROOT/codex-home.log" || fail 'doctor did not read CODEX_HOME'
printf '[mcp_servers.github]\nbearer_token_env_var = "GITHUB_MCP_PAT"\n' > "$custom_codex/config.toml"
TEST_CODEX_HOME="$custom_codex" run_bootstrap ubuntu native --check > "$TEST_ROOT/codex-home.log" || true
grep -q 'Legacy Codex GitHub MCP entry' "$TEST_ROOT/codex-home.log" || fail 'legacy entry in CODEX_HOME not reported'
TEST_CODEX_HOME="$TEST_ROOT/no-such-codex-home" run_bootstrap ubuntu native --configure-agents > "$TEST_ROOT/codex-home.log"
grep -q 'CODEX_HOME is set to .*not a directory' "$TEST_ROOT/codex-home.log" || fail 'missing CODEX_HOME not reported'
[ ! -e "$TEST_ROOT/no-such-codex-home" ] || fail 'bootstrap created a missing CODEX_HOME'
: > "$TEST_EVENTS"
TEST_MCP_LOOKALIKE=1 run_bootstrap ubuntu native --configure-agents > "$TEST_ROOT/mcp.log"
grep -q '^claude mcp get github$' "$TEST_EVENTS" && grep -q 'github is optional' "$TEST_ROOT/mcp.log" || fail 'lookalike MCP mistaken for github'
grep -q '^claude mcp add .* context7 ' "$TEST_EVENTS" || fail 'lookalike prevented context7 installation'
pass 'Auth scopes, legacy profile and Codex warnings, CODEX_HOME, and exact MCP names avoid false positives'

for tool in rustup uv; do
  mv "$TEST_ROOT/mock-bin/$tool" "$TEST_ROOT/$tool.saved"
done
result=0
run_bootstrap fedora native --check --stack=rust > "$TEST_ROOT/no-rustup.log" || result=$?
[ "$result" -eq 1 ] && grep -q 'rustup not installed' "$TEST_ROOT/no-rustup.log" || fail 'missing rustup is not a required failure'
# With no Rust at all, the one missing toolchain is one failure, not three.
for tool in rustc cargo; do mv "$TEST_ROOT/mock-bin/$tool" "$TEST_ROOT/$tool.saved"; done
result=0
run_bootstrap fedora native --check --stack=rust > "$TEST_ROOT/no-rust.log" || result=$?
[ "$result" -eq 1 ] && [ "$(grep -c 'FAIL' "$TEST_ROOT/no-rust.log")" -eq 1 ] \
  && grep -q 'rustc unavailable until rustup is installed' "$TEST_ROOT/no-rust.log" \
  && grep -q 'cargo tools skipped until rustup is installed' "$TEST_ROOT/no-rust.log" \
  || fail 'missing Rust toolchain was counted more than once'
for tool in rustc cargo; do mv "$TEST_ROOT/$tool.saved" "$TEST_ROOT/mock-bin/$tool"; done
pass 'A missing Rust toolchain is one required failure'
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
  DEVSETUP_KERNEL=Linux DEVSETUP_PROC_VERSION="$TEST_ROOT/os/wsl" bash "$ROOT/bootstrap-wsl.sh" --check > "$TEST_ROOT/wrapper.log"
grep -q 'WSL detected' "$TEST_ROOT/wrapper.log" || fail 'wrapper did not run the Linux bootstrap'
pass 'bootstrap-wsl.sh remains a compatible entry point'

# macOS: Homebrew instead of dnf/apt, no sudo, no WSL features.
: > "$TEST_EVENTS"
TEST_KERNEL=Darwin run_bootstrap fedora native --check > "$TEST_ROOT/mac.log"
grep -q 'macOS 15.0' "$TEST_ROOT/mac.log" && grep -q 'package manager: brew' "$TEST_ROOT/mac.log" || fail 'macOS not detected'
grep -q 'macOS opens sign-in pages' "$TEST_ROOT/mac.log" || fail 'macOS looked for the WSL bridge'
grep -q '^brew list --formula gh' "$TEST_EVENTS" || fail 'macOS packages not checked with brew'
if grep -Eq '^(sudo|dnf|apt-get|rpm|dpkg-query) ' "$TEST_EVENTS"; then fail 'macOS used a Linux package manager or sudo'; fi
if grep -q '^curl ' "$TEST_EVENTS"; then fail 'macOS check mode downloaded something'; fi
result=0
TEST_KERNEL=Darwin run_bootstrap fedora native --install-browser-bridge > /dev/null 2>&1 || result=$?
[ "$result" -eq 2 ] || fail 'browser bridge accepted on macOS'
: > "$TEST_EVENTS"
TEST_KERNEL=Darwin TEST_MISSING_PKGS=gh run_bootstrap fedora native > "$TEST_ROOT/mac-install.log"
grep -q '^brew install gh$' "$TEST_EVENTS" || fail 'macOS did not install the missing package with brew'
if grep -q '^sudo ' "$TEST_EVENTS"; then fail 'macOS package installation used sudo'; fi
pass 'macOS is detected and uses Homebrew without sudo or WSL features'
result=0
TEST_KERNEL=Darwin TEST_NO_CLT=1 run_bootstrap fedora native --check --stack=rust > "$TEST_ROOT/mac-rust.log" || result=$?
[ "$result" -ne 0 ] && grep -q 'Xcode Command Line Tools missing' "$TEST_ROOT/mac-rust.log" || fail 'missing Apple linker not reported for Rust'
grep -q '^brew list --formula pkgconf' "$TEST_EVENTS" || fail 'pkgconf not checked for Rust on macOS'
pass 'Rust on macOS requires the Command Line Tools linker and pkgconf'
mv "$TEST_ROOT/mock-bin/brew" "$TEST_ROOT/brew.saved"
: > "$TEST_EVENTS"
result=0
TEST_KERNEL=Darwin run_bootstrap fedora native > "$TEST_ROOT/mac-nobrew.log" 2>&1 || result=$?
[ "$result" -ne 0 ] && grep -q 'Homebrew is required' "$TEST_ROOT/mac-nobrew.log" || fail 'missing Homebrew not reported'
grep -q 'raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' "$TEST_ROOT/mac-nobrew.log" || fail 'Homebrew install command not shown'
if grep -Eq '^(brew|sudo|curl) ' "$TEST_EVENTS"; then fail 'bootstrap tried to install without Homebrew'; fi
mkdir -p "$TEST_ROOT/opt-brew"
mv "$TEST_ROOT/brew.saved" "$TEST_ROOT/opt-brew/brew"
TEST_KERNEL=Darwin TEST_BREW_CANDIDATES="$TEST_ROOT/opt-brew/brew" run_bootstrap fedora native --check > "$TEST_ROOT/mac-offpath.log"
if grep -q '^brew shellenv' "$TEST_EVENTS"; then fail 'check mode evaluated brew shellenv'; fi
grep -q 'package manager: brew' "$TEST_ROOT/mac-offpath.log" && grep -q 'not on PATH in new terminals' "$TEST_ROOT/mac-offpath.log" || fail 'Homebrew outside PATH not found or not explained'
mv "$TEST_ROOT/opt-brew/brew" "$TEST_ROOT/mock-bin/brew"
pass 'macOS without Homebrew stops with the official command; Homebrew off PATH is found and explained'
mv "$TEST_ROOT/mock-bin/code" "$TEST_ROOT/code.saved"
: > "$TEST_EVENTS"
TEST_KERNEL=Darwin run_bootstrap fedora native --check > "$TEST_ROOT/mac-nocode-check.log"
if grep -q '^brew install' "$TEST_EVENTS"; then fail 'check mode installed VS Code'; fi
grep -q 'brew install --cask visual-studio-code' "$TEST_ROOT/mac-nocode-check.log" || fail 'VS Code install command not shown'
TEST_KERNEL=Darwin run_bootstrap fedora native > "$TEST_ROOT/mac-nocode.log"
grep -q '^brew install --cask visual-studio-code' "$TEST_EVENTS" && grep -q 'VS Code installed' "$TEST_ROOT/mac-nocode.log" || fail 'VS Code not installed with Homebrew'
mv "$TEST_ROOT/code.saved" "$TEST_ROOT/mock-bin/code"
pass 'VS Code is installed with Homebrew on macOS, never in check mode'
env HOME="$TEST_ROOT/user" PATH="$TEST_ROOT/mock-bin:/usr/bin:/bin" DEVSETUP_KERNEL=Darwin \
  DEVSETUP_BREW_CANDIDATES="$TEST_ROOT/no-such-brew" bash "$ROOT/bootstrap-macos.sh" --check > "$TEST_ROOT/mac-wrapper.log"
grep -q 'macOS 15.0' "$TEST_ROOT/mac-wrapper.log" || fail 'bootstrap-macos.sh did not run the bootstrap'
result=0
run_bootstrap fedora native --stack= > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] || fail 'empty stack list accepted'
pass 'bootstrap-macos.sh is a working entry point; an empty stack list fails cleanly'

for legacy_token in '' fake-existing-token; do
  : > "$TEST_EVENTS"
  result=0
  env PATH="$TEST_ROOT/mock-bin:/usr/bin:/bin" GITHUB_MCP_PAT="$legacy_token" \
    bash "$ROOT/helpers/codex-with-github-mcp.sh" --version > "$TEST_ROOT/helper.log" 2>&1 || result=$?
  [ "$result" -eq 1 ] || fail 'retired launcher returned success'
  [ ! -s "$TEST_EVENTS" ] || fail 'retired launcher invoked a command'
  grep -q 'launcher is retired' "$TEST_ROOT/helper.log" || fail 'migration guidance missing'
  if grep -q 'fake-existing-token' "$TEST_ROOT/helper.log"; then fail 'retired launcher printed a credential'; fi
done
pass 'Retired Bash launcher never calls gh or Codex and prints only migration guidance'

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
# One command placeholder left is still unfinished; other {{...}} text in a real command is not.
sed -e 's/{{FORMAT_COMMAND}}/true/' -e 's/{{LINT_COMMAND}}/true/' \
    "$ROOT/templates/foundation/check.sh.template" > "$TEST_ROOT/project/scripts/one-left.sh"
result=0
bash "$TEST_ROOT/project/scripts/one-left.sh" > "$TEST_ROOT/one-left.log" 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -q 'placeholders' "$TEST_ROOT/one-left.log" || fail 'gate with one placeholder left did not refuse'
sed -e 's/{{FORMAT_COMMAND}}/true/' -e 's/{{LINT_COMMAND}}/true/' -e "s/{{TEST_COMMAND}}/printf '%s\\\\n' '{{TEMPLATE_NAME}}'/" \
    "$ROOT/templates/foundation/check.sh.template" > "$TEST_ROOT/project/scripts/braces.sh"
result=0
bash "$TEST_ROOT/project/scripts/braces.sh" > "$TEST_ROOT/braces.log" 2>&1 || result=$?
[ "$result" -eq 0 ] && grep -qx '{{TEMPLATE_NAME}}' "$TEST_ROOT/braces.log" || fail 'filled gate with {{...}} text in a command refused to run'
pass 'Bash gate refuses only its own command placeholders'
sed -e 's/{{FORMAT_COMMAND}}/true/' -e 's/{{LINT_COMMAND}}/true/' -e '/{{TEST_COMMAND}}/d' \
    "$ROOT/templates/foundation/check.sh.template" > "$TEST_ROOT/project/scripts/partial.sh"
bash "$TEST_ROOT/project/scripts/partial.sh" > /dev/null 2>&1 || fail 'gate with a deleted step failed'
sed -e '/^step "/d' "$ROOT/templates/foundation/check.sh.template" > "$TEST_ROOT/project/scripts/empty.sh"
result=0
bash "$TEST_ROOT/project/scripts/empty.sh" > "$TEST_ROOT/empty.log" 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -q 'no steps' "$TEST_ROOT/empty.log" || fail 'gate without steps reported success'
pass 'Bash gate allows deleting a step but refuses to pass with none'

# Scaffolder: real git in a temporary parent; stdin is never a terminal here.
NP="$TEST_ROOT/np"
new_project() {
  env DEVSETUP_KERNEL="${NP_OS:-Linux}" DEVSETUP_PROC_VERSION="$TEST_ROOT/os/${NP_KERNEL:-native}" \
    DEVSETUP_WSL_CONF="${NP_WSL_CONF:-$TEST_ROOT/no-wsl.conf}" bash "$ROOT/new-project.sh" "$@" < /dev/null
}
new_project --name demo --parent "$NP" --windows-native no --linux-target yes --stack python > "$TEST_ROOT/np.log"
for f in README.md PROJECT-CHARTER.md AGENTS.md CLAUDE.md scripts/check.sh .gitattributes .gitignore .editorconfig; do
  [ -f "$NP/demo/$f" ] || fail "scaffolder did not create $f"
done
[ -x "$NP/demo/scripts/check.sh" ] || fail 'scaffolded gate is not executable'
grep -A 1 '^\[Makefile\]$' "$NP/demo/.editorconfig" | grep -qx 'indent_style = tab' || fail 'generated Makefile tab policy missing'
# Editors must keep the CRLF that .gitattributes gives batch files; cmd.exe needs it.
grep -qx '\*\.bat text eol=crlf' "$NP/demo/.gitattributes" && grep -qx '\*\.cmd text eol=crlf' "$NP/demo/.gitattributes" \
  && grep -A 1 -Fx '[*.{bat,cmd}]' "$NP/demo/.editorconfig" | grep -qx 'end_of_line = crlf' \
  || fail 'generated .editorconfig and .gitattributes disagree on batch-file line endings'
[ "$(git -C "$NP/demo" symbolic-ref HEAD)" = refs/heads/main ] || fail 'scaffolded repository not on main'
if git -C "$NP/demo" rev-parse --verify -q HEAD > /dev/null; then fail 'scaffolder created a commit'; fi
grep -q 'Canonical development environment: LINUX' "$NP/demo/PROJECT-CHARTER.md" || fail 'environment not recorded'
grep -q 'Environment rationale: it runs on or deploys to Linux' "$NP/demo/PROJECT-CHARTER.md" || fail 'environment reason not recorded'
grep -q '{{LICENCE_OR_UNDECIDED}}' "$NP/demo/PROJECT-CHARTER.md" || fail 'undecided charter fields were filled in'
grep -q 'uv run --locked ruff check' "$NP/demo/scripts/check.sh" && grep -qx '.venv/' "$NP/demo/.gitignore" || fail 'Python stack not applied'
if grep -q '{{[A-Z_][A-Z_]*}}' "$NP/demo/scripts/check.sh"; then fail 'stack gate kept placeholders'; fi
if grep -q 'Copy this gate' "$NP/demo/scripts/check.sh"; then fail 'scaffolded gate tells the reader to copy itself'; fi
if grep -q 'CI runs the same gate' "$NP/demo/README.md" || grep -q 'CI invokes the same gate' "$NP/demo/AGENTS.md"; then
  fail 'generated files claim CI that was not created'
fi
if grep -rl --exclude-dir=.git $'\r' "$NP/demo" | grep -q .; then fail 'scaffolder wrote CRLF'; fi
pass 'Scaffolder creates an uncommitted Linux repository and records the environment and reason'
new_project --name plain --parent "$NP" --environment linux --no-claude > /dev/null
[ ! -e "$NP/plain/CLAUDE.md" ] || fail '--no-claude ignored'
result=0; (cd "$NP/plain" && ./scripts/check.sh) > "$TEST_ROOT/np-gate.log" 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -q 'placeholders' "$TEST_ROOT/np-gate.log" || fail 'unfilled scaffolded gate did not refuse'
pass 'Scaffolded gate without a chosen stack refuses to run'
result=0; new_project --name wintool --parent "$NP" --windows-native yes --linux-target no > "$TEST_ROOT/np-win.log" || result=$?
[ "$result" -eq 3 ] && [ ! -e "$NP/wintool" ] && grep -q 'new-project.ps1' "$TEST_ROOT/np-win.log" || fail 'Windows project was created on Linux'
# Refusals happen up front: the user sees why, and no staging directory is left.
stage_count() { set -- "$NP"/.devsetup-stage.*; if [ -e "$1" ]; then echo "$#"; else echo 0; fi; }
printf 'keep\n' > "$NP/demo/sentinel"
stages=$(stage_count)
result=0; new_project --name demo --parent "$NP" --environment linux > "$TEST_ROOT/np-existing.log" 2>&1 || result=$?
[ "$result" -eq 1 ] && grep -qx keep "$NP/demo/sentinel" || fail 'scaffolder touched an existing project'
grep -q 'not an empty directory; nothing was changed' "$TEST_ROOT/np-existing.log" && [ "$(stage_count)" = "$stages" ] \
  || fail 'existing project was not refused before staging'
result=0; new_project --name ../escape --parent "$NP" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && [ ! -e "$TEST_ROOT/escape" ] || fail 'unsafe name accepted'
result=0; new_project --name -dash --parent "$NP" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && [ ! -e "$NP/-dash" ] || fail 'option-shaped name accepted'
# Names Windows cannot hold are refused; similar ordinary names still pass validation.
for reserved in con NUL Com1 lpt9.txt aux.tar.gz name.; do
  result=0; new_project --name "$reserved" --parent "$NP" --environment linux > "$TEST_ROOT/reserved.log" 2>&1 || result=$?
  [ "$result" -eq 1 ] && [ ! -e "$NP/$reserved" ] && grep -Eq 'reserved device name|must not end' "$TEST_ROOT/reserved.log" \
    || fail "Windows-reserved name accepted: $reserved"
done
for ordinary in console com10 nul-tools v1.0; do
  result=0; new_project --name "$ordinary" --parent "$NP" --environment windows > /dev/null 2>&1 || result=$?
  [ "$result" -eq 3 ] || fail "ordinary name rejected: $ordinary"
done
pass 'Scaffolder refuses names Windows reserves and accepts similar ordinary names'
result=0; new_project --name asks --parent "$NP" > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && [ ! -e "$NP/asks" ] || fail 'missing answers were guessed'
result=0; NP_KERNEL=wsl new_project --name onwindows --parent /mnt/c/src --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] || fail 'WSL project accepted on the Windows filesystem'
pass 'Scaffolder refuses the wrong platform, existing projects, unsafe names, guesses and /mnt in WSL'
# The WSL guard judges the real location, not the spelling of the path, and follows
# a drive mount root moved by /etc/wsl.conf. Drives are fixture directories here.
WINROOT="$TEST_ROOT/winroot"
mkdir -p "$WINROOT/c/src" "$WINROOT/data"
printf '[automount]\nroot = %s/ # moved drives\n' "$WINROOT" > "$TEST_ROOT/wsl-moved.conf"
result=0; NP_KERNEL=wsl NP_WSL_CONF="$TEST_ROOT/wsl-moved.conf" new_project --name moved --parent "$WINROOT/c/src" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && [ ! -e "$WINROOT/c/src/moved" ] || fail 'WSL project accepted on a drive under a custom mount root'
if ln -s "$WINROOT/c" "$NP/winlink" 2>/dev/null && [ -L "$NP/winlink" ]; then
  result=0; NP_KERNEL=wsl NP_WSL_CONF="$TEST_ROOT/wsl-moved.conf" new_project --name vialink --parent "$NP/winlink/new" --environment linux > /dev/null 2>&1 || result=$?
  [ "$result" -eq 1 ] && [ ! -e "$WINROOT/c/new" ] || fail 'WSL project accepted through a symlink onto a Windows drive'
  rm -f -- "$NP/winlink"
else
  rm -rf -- "$NP/winlink"
  echo 'SKIP: host cannot create a real symbolic link; symlink onto a Windows drive not exercised'
fi
NP_KERNEL=wsl NP_WSL_CONF="$TEST_ROOT/wsl-moved.conf" new_project --name notadrive --parent "$WINROOT/data" --environment linux > /dev/null \
  || fail 'WSL project refused in a non-drive directory under the mount root'
[ -d "$WINROOT/data/notadrive/.git" ] || fail 'WSL project under the mount root was not created'
printf '[automount]\nroot = "/"\n' > "$TEST_ROOT/wsl-root.conf"
result=0; NP_KERNEL=wsl NP_WSL_CONF="$TEST_ROOT/wsl-root.conf" new_project --name rooted --parent /c/src --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] || fail 'WSL project accepted on /c with mount root /'
pass 'WSL location guard follows the configured drive mount root and symlinks'
result=0; NP_KERNEL=wsl new_project --name climbs --parent "$NP/not-yet/../../escape" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -eq 1 ] && [ ! -e "$NP/not-yet" ] && [ ! -e "$TEST_ROOT/escape" ] || fail "WSL guard accepted '..' in a missing path"
pass "Scaffolder resolves symlinks and refuses '..' before checking the WSL location"
# A failure part-way through removes what the run created, so a rerun can start clean.
mkdir -p "$TEST_ROOT/failgit"
printf '#!/usr/bin/env bash\ncase "$1" in init) echo "fatal: simulated failure" >&2; exit 1 ;; esac\n' > "$TEST_ROOT/failgit/git"
chmod +x "$TEST_ROOT/failgit/git"
fail_project() {
  env PATH="$TEST_ROOT/failgit:$PATH" DEVSETUP_KERNEL=Linux DEVSETUP_PROC_VERSION="$TEST_ROOT/os/native" \
    bash "$ROOT/new-project.sh" "$@" < /dev/null
}
result=0; fail_project --name broken --parent "$NP" --environment linux > "$TEST_ROOT/np-broken.log" 2>&1 || result=$?
[ "$result" -ne 0 ] && [ ! -e "$NP/broken" ] && grep -q 'destination files were preserved' "$TEST_ROOT/np-broken.log" || fail 'failed preparation touched the destination'
mkdir -p "$NP/wasempty"
result=0; fail_project --name wasempty --parent "$NP" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -ne 0 ] && [ -d "$NP/wasempty" ] && [ -z "$(ls -A -- "$NP/wasempty")" ] || fail 'failed scaffold did not restore the empty target'
pass 'A failed scaffold removes only what it created'
# Inspect git init's actual location without relying on the test host filesystem.
cat > "$TEST_ROOT/failgit/git" <<'STAGING'
#!/usr/bin/env bash
if [ "$1" = init ]; then
  for target; do :; done
  expected_parent=$(cd -P -- "$TEST_PARENT" && pwd -P) || exit 92
  case "$target" in "$expected_parent"/.devsetup-stage.*/project) exit 0;; *) exit 91;; esac
fi
STAGING
TEST_PARENT="$NP" fail_project --name sibling --parent "$NP" --environment linux > /dev/null
pass 'Git initializes in staging on the destination filesystem'
if ln -s "$NP" "$TEST_ROOT/np-alias" 2>/dev/null && [ -L "$TEST_ROOT/np-alias" ]; then
  TEST_PARENT="$TEST_ROOT/np-alias" fail_project --name sibling-alias --parent "$TEST_ROOT/np-alias" --environment linux > /dev/null
  pass 'Staging filesystem check accepts a parent with a symbolic-link spelling'
else
  echo 'SKIP: host cannot create a real symbolic-link parent'
fi
# Simulate a concurrent writer during preparation. The destination was empty at
# validation but now contains someone else's file when publication starts.
mkdir -p "$NP/concurrent"
cat > "$TEST_ROOT/failgit/git" <<'CONCURRENT'
#!/usr/bin/env bash
printf 'keep\n' > "$TEST_DESTINATION/sentinel"
exit 0
CONCURRENT
result=0
TEST_DESTINATION="$NP/concurrent" fail_project --name concurrent --parent "$NP" --environment linux > /dev/null 2>&1 || result=$?
[ "$result" -ne 0 ] && grep -qx keep "$NP/concurrent/sentinel" || fail 'concurrent destination data was lost'
[ ! -e "$NP/concurrent/README.md" ] || fail 'concurrent destination was partially published'
pass 'A concurrent writer prevents publication and its files survive'
# Native Unix supports real symlinks; Git Bash may require Windows privileges.
mkdir -p "$NP/link-target"
if ln -s "$NP/link-target" "$NP/linked" 2>/dev/null && [ -L "$NP/linked" ]; then
  stages=$(stage_count)
  result=0; new_project --name linked --parent "$NP" --environment linux > "$TEST_ROOT/np-linked.log" 2>&1 || result=$?
  [ "$result" -ne 0 ] && [ -z "$(ls -A -- "$NP/link-target")" ] || fail 'target symlink was followed'
  grep -q 'is a symbolic link; nothing was changed' "$TEST_ROOT/np-linked.log" && [ "$(stage_count)" = "$stages" ] \
    || fail 'symlinked destination was not refused before staging'
  pass 'Scaffolder refuses a symlink at the final project directory'
else
  echo 'SKIP: host cannot create a real symbolic link'
fi
result=0
new_project --name winoptions --parent "$NP" --environment windows --stack rust --no-claude > "$TEST_ROOT/handoff.log" || result=$?
[ "$result" -eq 3 ] && grep -q -- '-Stack rust -NoClaude' "$TEST_ROOT/handoff.log" || fail 'Windows handoff lost selections'
pass 'Windows handoff preserves stack and Claude selection'
# Choices are case-insensitive, as in new-project.ps1.
new_project --name mixedcase --parent "$NP" --environment Linux --stack Python > /dev/null || fail 'mixed-case environment or stack rejected'
grep -q 'uv run --locked ruff check' "$NP/mixedcase/scripts/check.sh" || fail 'mixed-case stack not applied'
result=0
new_project --name winmixed --parent "$NP" --environment WINDOWS --stack RUST > "$TEST_ROOT/handoff-case.log" || result=$?
[ "$result" -eq 3 ] && grep -q -- '-Environment Windows -Stack rust' "$TEST_ROOT/handoff-case.log" || fail 'upper-case Windows handoff failed'
pass 'Scaffolder accepts environment and stack in any case'
# pytest exits 5 with no tests, so the printed steps must ask for one before the gate.
new_project --name pysteps --parent "$NP" --environment linux --stack python > "$TEST_ROOT/np-python.log"
grep -q 'pytest fails when it finds no tests: add a first test before step 5' "$TEST_ROOT/np-python.log" \
  || fail 'Python next steps omit the first-test requirement'
# python -m pytest puts the project on the import path so a first test can import main.py.
grep -Fq 'uv run --locked python -m pytest -q' "$NP/pysteps/scripts/check.sh" || fail 'Python gate does not run pytest through python -m'
# --locked on every uv step: a stale uv.lock must fail the gate, never be rewritten.
[ "$(grep -c 'uv run --locked ' "$NP/pysteps/scripts/check.sh")" -eq 3 ] || fail 'Python gate has a uv step without --locked'
pass 'Python next steps require a first test before the gate'
# The Rust next step keeps the scaffolder's single /target/ entry: plain cargo init
# would append another. Cargo runs only where installed; it needs no network here.
new_project --name rusty --parent "$NP" --environment linux --stack rust > "$TEST_ROOT/np-rust.log"
grep -q 'cargo init --vcs none   then   cargo generate-lockfile' "$TEST_ROOT/np-rust.log" \
  || fail 'Rust next step does not use cargo init --vcs none and create Cargo.lock'
grep -Fq 'cargo clippy --locked ' "$NP/rusty/scripts/check.sh" && grep -Fq 'cargo test --locked ' "$NP/rusty/scripts/check.sh" \
  || fail 'Rust gate does not pass --locked'
if command -v cargo >/dev/null 2>&1; then
  (cd "$NP/rusty" && cargo init --vcs none --quiet) > "$TEST_ROOT/cargo-init.log" 2>&1 || fail 'cargo init --vcs none failed in a scaffolded project'
  [ "$(grep -c 'target' "$NP/rusty/.gitignore")" -eq 1 ] && grep -qx '/target/' "$NP/rusty/.gitignore" \
    || fail 'cargo init changed the scaffolded .gitignore'
  pass 'Rust next step leaves one /target entry after cargo init'
  # The printed lockfile step lets the gate's --locked pass; a stale lockfile then
  # fails without being rewritten. Metadata applies the same check without a build.
  (cd "$NP/rusty" && CARGO_NET_OFFLINE=true cargo generate-lockfile --quiet \
    && CARGO_NET_OFFLINE=true cargo metadata --locked --format-version 1 > /dev/null) > "$TEST_ROOT/cargo-lock.log" 2>&1 \
    || fail 'fresh Rust project fails --locked after cargo generate-lockfile'
  cp "$NP/rusty/Cargo.lock" "$TEST_ROOT/Cargo.lock.before"
  sed 's/^version = "0.1.0"$/version = "0.2.0"/' "$NP/rusty/Cargo.toml" > "$TEST_ROOT/Cargo.toml.new"
  grep -qx 'version = "0.2.0"' "$TEST_ROOT/Cargo.toml.new" || fail 'Cargo.toml fixture version not found'
  mv "$TEST_ROOT/Cargo.toml.new" "$NP/rusty/Cargo.toml"
  if (cd "$NP/rusty" && CARGO_NET_OFFLINE=true cargo metadata --locked --format-version 1 > /dev/null 2>&1); then
    fail 'stale Cargo.lock passed --locked'
  fi
  cmp -s "$TEST_ROOT/Cargo.lock.before" "$NP/rusty/Cargo.lock" || fail '--locked rewrote Cargo.lock'
  pass 'Rust lockfile step satisfies --locked, and a stale Cargo.lock fails without being rewritten'
else
  echo 'SKIP: cargo is not installed; cargo init not exercised'
fi
NP_OS=Darwin new_project --name macapp --parent "$NP" --windows-native no --linux-target yes > /dev/null
grep -q 'Canonical development environment: MACOS' "$NP/macapp/PROJECT-CHARTER.md" || fail 'macOS environment not recorded'
grep -q 'container or Linux VM' "$NP/macapp/PROJECT-CHARTER.md" || fail 'macOS Linux-target reason not recorded'
result=0; NP_OS=Darwin new_project --name macwin --parent "$NP" --windows-native yes --linux-target no > "$TEST_ROOT/np-macwin.log" || result=$?
[ "$result" -eq 3 ] && [ ! -e "$NP/macwin" ] && grep -q 'Windows virtual machine' "$TEST_ROOT/np-macwin.log" || fail 'Windows project was created on macOS'
pass 'Scaffolder records macOS and sends Windows-native projects to Windows'

# Commit identity check: real Git in a temporary repository, identities set per commit.
OWNER=owner@users.noreply.github.com
ID="$TEST_ROOT/identity"
git init -q -b main "$ID"
commit_as() { # commit_as NAME EMAIL COMMITTER_EMAIL MESSAGE
  env GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME=committer \
    GIT_COMMITTER_EMAIL="$3" git -C "$ID" -c commit.gpgsign=false commit -q --allow-empty -m "$4"
}
# The check reads the repository in its working directory.
check_identity() { (cd "$ID" && env ALLOWED_EMAILS="$OWNER" bash "$ROOT/scripts/check-commit-identity.sh" "$1") > "$TEST_ROOT/identity.log" 2>&1; }
commit_as owner "$OWNER" "$OWNER" 'feat: owner commit'
commit_as owner "$OWNER" noreply@github.com 'Merge pull request #1 from owner/topic'
check_identity main || fail 'owner commits and a website merge were rejected'
grep -q '^ok: 2 commit' "$TEST_ROOT/identity.log" || fail 'identity check did not report the commits it checked'
pass 'Identity check accepts the owner and GitHub website merges'
# Ordinary prose that resembles an attribution line must not fail the check.
git -C "$ID" switch -q -c prose main
commit_as owner "$OWNER" "$OWNER" $'docs: explain templates\n\nGenerated by new-project.sh, these files are templates.'
commit_as owner "$OWNER" "$OWNER" $'fix: record notes\n\nDebug-session: see notes\nGenerated with care by the maintainer.'
commit_as owner "$OWNER" "$OWNER" $'docs: review policy\n\nExplain why files generated by Claude Code are reviewed.'
check_identity prose || fail 'ordinary prose was mistaken for attribution'
pass 'Identity check accepts prose that only resembles attribution'
bad_case() { # bad_case BRANCH EXPECTED_OUTPUT NAME EMAIL COMMITTER_EMAIL MESSAGE
  local branch="$1" expected="$2"; shift 2
  git -C "$ID" switch -q -c "$branch" main
  commit_as "$@"
  if check_identity "$branch"; then fail "identity check accepted $branch"; fi
  grep -q "$expected" "$TEST_ROOT/identity.log" || fail "identity check did not explain $branch"
}
bad_case claude-author 'author Claude <noreply@anthropic.com>' Claude noreply@anthropic.com "$OWNER" 'chore: work'
bad_case bot-author 'author dependabot' 'dependabot[bot]' 49699333+dependabot[bot]@users.noreply.github.com "$OWNER" 'chore: bump'
bad_case other-committer 'committer committer <someone@example.com>' owner "$OWNER" someone@example.com 'chore: work'
bad_case co-author 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>'
bad_case lowercase-co-author 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\nco-authored-by: Someone <s@example.com>'
bad_case session-link 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\nClaude-Session: https://claude.ai/code/session_x'
bad_case generated-line 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\nGenerated with [Claude Code](https://claude.com/claude-code)'
bad_case generated-other 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\nGenerated-by: another tool'
bad_case generated-emoji 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\n\xf0\x9f\xa4\x96 Generated with [Claude Code](https://claude.com/claude-code)'
bad_case generated-tool 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\nGenerated with Codex'
bad_case other-session 'co-author or attribution line' owner "$OWNER" "$OWNER" $'fix: work\n\nCodex-Session: https://example.invalid/session'
pass 'Identity check rejects Claude, bot and foreign identities and every attribution line'
# Avoid command-line size limits; an early match must survive a message larger
# than the pipe buffer on every platform (including Windows Git Bash).
git -C "$ID" switch -q -c long-message main
{
  printf 'fix: long message\n\nCo-authored-by: Other <other@example.invalid>\n\n'
  awk 'BEGIN { for (i=0; i<50000; i++) print "unrelated message padding" }'
} > "$TEST_ROOT/long-message.txt"
env GIT_AUTHOR_NAME=owner GIT_AUTHOR_EMAIL="$OWNER" GIT_COMMITTER_NAME=owner GIT_COMMITTER_EMAIL="$OWNER" \
  git -C "$ID" -c commit.gpgsign=false commit -q --allow-empty -F "$TEST_ROOT/long-message.txt"
if check_identity long-message; then fail 'long message bypassed attribution policy'; fi
grep -q 'co-author or attribution line' "$TEST_ROOT/identity.log" || fail 'long message was not diagnosed'
pass 'Identity check rejects attribution before a long message body'

# grep can exist but fail at runtime; a Git message-read failure must also fail closed.
mkdir -p "$TEST_ROOT/failing-matcher" "$TEST_ROOT/failing-message"
printf '#!/bin/sh\nexit 2\n' > "$TEST_ROOT/failing-matcher/grep"
real_git=$(command -v git)
printf '#!/bin/sh\ncase "$*" in *--format=%%B*) exit 73;; esac\nexec "%s" "$@"\n' "$real_git" > "$TEST_ROOT/failing-message/git"
chmod +x "$TEST_ROOT/failing-matcher/grep" "$TEST_ROOT/failing-message/git"
for scenario in failing-matcher failing-message; do
  result=0
  (cd "$ID" && PATH="$TEST_ROOT/$scenario:$PATH" ALLOWED_EMAILS="$OWNER" bash "$ROOT/scripts/check-commit-identity.sh" main) > "$TEST_ROOT/$scenario.log" 2>&1 || result=$?
  [ "$result" -ne 0 ] || fail "$scenario incorrectly passed"
  grep -Eq 'attribution matcher failed|could not read commit message' "$TEST_ROOT/$scenario.log" || fail "$scenario lacked a diagnostic"
done
pass 'Identity check fails closed on matcher and message-read errors'

result=0
(cd "$ID" && env -u ALLOWED_EMAILS bash "$ROOT/scripts/check-commit-identity.sh" main) > "$TEST_ROOT/identity.log" 2>&1 || result=$?
[ "$result" -ne 0 ] || fail 'identity check ran without an allowed identity'
result=0
(cd "$ID" && env ALLOWED_EMAILS="$OWNER" bash "$ROOT/scripts/check-commit-identity.sh" no-such-branch) > "$TEST_ROOT/identity.log" 2>&1 || result=$?
[ "$result" -ne 0 ] || fail 'identity check passed with no commits to check'
pass 'Identity check fails closed without configuration or commits'
# A missing grep must not turn the forbidden-attribution check into a success.
mkdir -p "$TEST_ROOT/identity-no-grep"
cp "$TEST_ROOT/mock-bin/git" "$TEST_ROOT/identity-no-grep/git"
result=0
env PATH="$TEST_ROOT/identity-no-grep" ALLOWED_EMAILS="$OWNER" "$BASH" \
  "$ROOT/scripts/check-commit-identity.sh" HEAD > "$TEST_ROOT/missing-grep.log" 2>&1 || result=$?
[ "$result" -ne 0 ] && grep -q 'required command unavailable: grep' "$TEST_ROOT/missing-grep.log" || fail 'identity check passed without grep'
pass 'Identity check fails closed when its attribution matcher is unavailable'

echo 'Bash regressions passed.'
