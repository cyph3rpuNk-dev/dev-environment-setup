#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# new-project.sh : start a new repository from the toolkit's foundation templates
#
#   bash new-project.sh                         # asks what it needs
#   bash new-project.sh --name my-tool --windows-native no --linux-target yes
#   bash new-project.sh --name my-tool --environment linux --stack python
#
# Runs on Linux, in WSL and on macOS. "linux" means a Linux-targeted project, which
# on a Mac is developed natively with containers or a VM for Linux-only parts.
#
# Options:
#   --name NAME                 repository directory name (letters, digits, . _ -)
#   --parent DIR                where to create it (default: ~/src)
#   --environment linux|windows skip the questions and use this environment
#   --windows-native yes|no     builds/runs as a native Windows program?
#   --linux-target yes|no       runs on or deploys to Linux?
#   --stack none|rust|python    pre-fill the gate with that stack's usual commands
#   --no-claude                 do not create CLAUDE.md
#
# It creates files and runs 'git init' only in a new or empty directory, and never
# commits. Undecided charter fields stay as visible {{...}} placeholders.
# ---------------------------------------------------------------------------
set -uo pipefail
TOOLKIT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || exit 1
TEMPLATES="$TOOLKIT/templates/foundation"

usage() { sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { echo "new-project: $*" >&2; exit 1; }

NAME="" PARENT="$HOME/src" ENVIRONMENT="" WINDOWS_NATIVE="" LINUX_TARGET="" STACK=none CLAUDE=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --name) NAME=${2-}; shift ;;
    --name=*) NAME=${1#*=} ;;
    --parent) PARENT=${2-}; shift ;;
    --parent=*) PARENT=${1#*=} ;;
    --environment) ENVIRONMENT=${2-}; shift ;;
    --environment=*) ENVIRONMENT=${1#*=} ;;
    --windows-native) WINDOWS_NATIVE=${2-}; shift ;;
    --windows-native=*) WINDOWS_NATIVE=${1#*=} ;;
    --linux-target) LINUX_TARGET=${2-}; shift ;;
    --linux-target=*) LINUX_TARGET=${1#*=} ;;
    --stack) STACK=${2-}; shift ;;
    --stack=*) STACK=${1#*=} ;;
    --no-claude) CLAUDE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1
ask() { # ask VAR "question"
  local answer
  [ "$INTERACTIVE" = 1 ] || die "missing $1; pass it as an option (see --help)"
  read -r -p "$2 " answer || die "no answer for $1"
  printf -v "$1" '%s' "$answer"
}
yes_no() { # normalise yes/no answers, rejecting anything else
  case "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" in
    y|yes) printf -v "$1" yes ;;
    n|no) printf -v "$1" no ;;
    *) die "answer yes or no for $1 (got '$2')" ;;
  esac
}

[ -n "$NAME" ] || ask NAME "Repository name (for example my-tool):"
case "$NAME" in
  ''|.*|-*|*[!A-Za-z0-9._-]*) die "name must use letters, digits, '.', '_' or '-', and not start with '.' or '-'" ;;
esac
# Windows cannot hold these names (with any extension) or a trailing dot, so such a
# repository could not be checked out there.
NAME_LOWER=$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')
case "${NAME_LOWER%%.*}" in
  con|prn|aux|nul|com[0-9]|lpt[0-9]) die "'$NAME' is a reserved device name on Windows; choose another name" ;;
esac
case "$NAME" in *.) die "name must not end with '.'" ;; esac
case "$STACK" in none|rust|python) ;; *) die "unknown stack '$STACK' (none, rust, python)" ;; esac

# --- Choose the environment -------------------------------------------------
REASON=""
case "$ENVIRONMENT" in
  linux|windows) REASON="chosen explicitly" ;;
  '') ;;
  *) die "environment must be linux or windows" ;;
esac
if [ -z "$ENVIRONMENT" ]; then
  [ -n "$WINDOWS_NATIVE" ] || ask WINDOWS_NATIVE "Will it build or run as a native Windows program (Windows APIs, .exe, MSVC, Windows-only SDKs or hardware)? [yes/no]"
  yes_no WINDOWS_NATIVE "$WINDOWS_NATIVE"
  [ -n "$LINUX_TARGET" ] || ask LINUX_TARGET "Will it run on or deploy to Linux (web server, PHP/WordPress, containers, Linux services or tools)? [yes/no]"
  yes_no LINUX_TARGET "$LINUX_TARGET"
  case "$WINDOWS_NATIVE/$LINUX_TARGET" in
    yes/no) ENVIRONMENT=windows; REASON="it builds or runs as a native Windows program" ;;
    no/yes) ENVIRONMENT=linux; REASON="it runs on or deploys to Linux" ;;
    no/no) ENVIRONMENT=linux; REASON="no platform tie was identified, so it starts where it is being created; revisit if a dependency requires Windows" ;;
    yes/yes)
      echo "It targets both Windows and Linux. Pick one canonical development side;"
      echo "the other becomes a CI or compatibility target."
      ask ENVIRONMENT "Canonical side [linux/windows]:"
      case "$ENVIRONMENT" in linux|windows) ;; *) die "environment must be linux or windows" ;; esac
      REASON="cross-platform; $ENVIRONMENT is canonical and the other platform must be covered by CI" ;;
  esac
fi

KERNEL=${DEVSETUP_KERNEL:-$(uname -s 2>/dev/null)}
PROC_VERSION=${DEVSETUP_PROC_VERSION:-/proc/version}
IS_WSL=0
if [ "$KERNEL" != Darwin ] && grep -qi microsoft "$PROC_VERSION" 2>/dev/null; then IS_WSL=1; fi

if [ "$ENVIRONMENT" = windows ]; then
  stack_option=""; claude_option=""
  [ "$STACK" = none ] || stack_option=" -Stack $STACK"
  [ "$CLAUDE" = 1 ] || claude_option=" -NoClaude"
  echo "Recommended environment: native Windows, because $REASON."
  echo "Create it from PowerShell on a Windows PC or Windows virtual machine instead:"
  echo "  powershell -NoProfile -File .\\new-project.ps1 -Name $NAME -Environment Windows$stack_option$claude_option"
  echo "Nothing was created."
  exit 3
fi

case "$PARENT" in /*) ;; *) PARENT="$PWD/$PARENT" ;; esac
if [ "$IS_WSL" = 1 ]; then
  # Judge where the project would really land: resolve symlinks and '..' in the part
  # of the path that exists. A missing part may not contain '..', which could climb
  # back out of it.
  existing=$PARENT missing=""
  while [ ! -d "$existing" ]; do
    missing="/${existing##*/}$missing"
    existing=${existing%/*}
    [ -n "$existing" ] || existing=/
  done
  case "$missing/" in */../*) die "use a --parent path without '..' in the part that does not exist yet" ;; esac
  base=$(cd -P -- "$existing" && pwd -P) || die "cannot resolve $PARENT"
  # When nothing below / exists (no /mnt at all), base is "/"; avoid joining to "//mnt".
  resolved="${base%/}$missing"
  case "$resolved/" in
    /mnt/*) die "$PARENT is on the Windows filesystem ($resolved). Linux projects belong on the Linux filesystem, for example ~/src" ;;
  esac
fi
TARGET="$PARENT/$NAME"
if [ -L "$TARGET" ]; then
  die "$TARGET is a symbolic link; nothing was changed"
fi
if [ -e "$TARGET" ] && { [ ! -d "$TARGET" ] || [ -n "$(ls -A -- "$TARGET")" ]; }; then
  die "$TARGET already exists and is not an empty directory; nothing was changed"
fi
command -v git >/dev/null 2>&1 || die "git is required; run bootstrap-linux.sh first"
for f in PROJECT-CHARTER.md.template AGENTS.md.template CLAUDE.md.template check.sh.template \
         README.md.template gitattributes.template gitignore.template editorconfig.template; do
  [ -f "$TEMPLATES/$f" ] || die "toolkit template missing: $TEMPLATES/$f"
done

if [ "$KERNEL" = Darwin ]; then
  ENV_LABEL=MACOS; ENV_TEXT="macOS"
  case "$LINUX_TARGET" in yes) REASON="$REASON; on this Mac it is developed natively, with a container or Linux VM for anything Linux-only" ;; esac
elif [ "$IS_WSL" = 1 ]; then ENV_LABEL=WSL; ENV_TEXT="Linux (WSL)"
else ENV_LABEL=LINUX; ENV_TEXT="Linux"; fi
GATE="./scripts/check.sh"

case "$STACK" in
  rust)
    FORMAT='cargo fmt --all -- --check'
    LINT='cargo clippy --workspace --all-targets -- -D warnings'
    TEST='cargo test --workspace'
    IGNORE_EXTRA=$'\n# Rust build output\n/target/' ;;
  python)
    FORMAT='uv run ruff format --check .'
    LINT='uv run ruff check .'
    TEST='uv run pytest -q'
    IGNORE_EXTRA=$'\n# Python environments and caches\n.venv/\n__pycache__/\n.pytest_cache/\n.ruff_cache/\n.mypy_cache/' ;;
  *) FORMAT='' LINT='' TEST='' IGNORE_EXTRA='' ;;
esac

# Replace {{KEY}} with VALUE literally. awk reads both through the environment, so
# '&', '/' and backslashes stay literal, and the result is the same in Bash 3.2
# (macOS) and newer versions.
render() { # render TEMPLATE OUTPUT KEY VALUE ...
  local out="$2"
  cp -- "$TEMPLATES/$1" "$out" || return 1
  shift 2
  while [ "$#" -ge 2 ]; do
    RENDER_KEY="{{$1}}" RENDER_VALUE="$2" awk '
      { line = $0; result = ""; key = ENVIRON["RENDER_KEY"]; value = ENVIRON["RENDER_VALUE"]
        while ((i = index(line, key)) > 0) { result = result substr(line, 1, i - 1) value; line = substr(line, i + length(key)) }
        print result line }' "$out" > "$out.tmp" && mv -- "$out.tmp" "$out" || return 1
    shift 2
  done
}

# Stage beside the destination so Git probes the destination filesystem.
# Never recursively delete a user-selected path.
DESTINATION=$TARGET
mkdir -p -- "$PARENT" || die "cannot create parent directory"
STAGING=$(mktemp -d "$PARENT/.devsetup-stage.XXXXXXXX") || die "cannot create a private staging directory"
STAGING=$(cd -P -- "$STAGING" && pwd -P) || die "cannot resolve staging directory"
TARGET="$STAGING/project"
CREATED=0
cleanup_partial() {
  if [ "$CREATED" = 1 ]; then
    # Only the absolute mktemp directory may be removed, never the destination.
    if [ ! -L "$STAGING" ] && [ "$(cd -P -- "$STAGING" && pwd -P)" = "$STAGING" ]; then
      rm -rf -- "$STAGING" || echo "new-project: could not clean staging at $STAGING" >&2
      return
    fi
  else
    echo "new-project: setup failed; destination files were preserved at $DESTINATION" >&2
  fi
  echo "new-project: staging directory retained at $STAGING" >&2
}
trap cleanup_partial EXIT
set -e
mkdir -p -- "$TARGET/scripts"
render README.md.template "$TARGET/README.md" PROJECT_NAME "$NAME" ENVIRONMENT "$ENV_TEXT" GATE_COMMAND "$GATE"
render PROJECT-CHARTER.md.template "$TARGET/PROJECT-CHARTER.md" \
  PROJECT_NAME "$NAME" \
  'IDEA | PROTOTYPE | ACTIVE | MAINTENANCE' IDEA \
  'WINDOWS | LINUX | MACOS | WSL | UNDECIDED' "$ENV_LABEL" \
  WHY_THIS_ENVIRONMENT "$REASON" \
  GATE_COMMAND "$GATE"
render AGENTS.md.template "$TARGET/AGENTS.md" PROJECT_NAME "$NAME" GATE_COMMAND "$GATE"
if [ "$CLAUDE" = 1 ]; then render CLAUDE.md.template "$TARGET/CLAUDE.md"; fi
if [ "$STACK" = none ]; then
  render check.sh.template "$TARGET/scripts/check.sh"
else
  render check.sh.template "$TARGET/scripts/check.sh" FORMAT_COMMAND "$FORMAT" LINT_COMMAND "$LINT" TEST_COMMAND "$TEST"
fi
chmod +x "$TARGET/scripts/check.sh"
render gitattributes.template "$TARGET/.gitattributes"
render gitignore.template "$TARGET/.gitignore"
if [ -n "$IGNORE_EXTRA" ]; then printf '%s\n' "$IGNORE_EXTRA" >> "$TARGET/.gitignore"; fi
render editorconfig.template "$TARGET/.editorconfig"
git init --quiet -- "$TARGET"
git -C "$TARGET" symbolic-ref HEAD refs/heads/main

# Publish with exclusive file creation. mkdir must also succeed exclusively for
# each child directory. If another process changes the destination, preserve both
# its files and any files already published; do not attempt recursive rollback.
publish_tree() {
  local source="$1" destination="$2" entry name
  for entry in "$source"/* "$source"/.[!.]* "$source"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name=${entry##*/}
    [ ! -L "$entry" ] || { echo "Refusing staged symlink: $entry" >&2; return 1; }
    if [ -d "$entry" ]; then
      mkdir -- "$destination/$name" || return 1
      publish_tree "$entry" "$destination/$name" || return 1
    elif [ -f "$entry" ]; then
      (set -C; cat -- "$entry" > "$destination/$name") || return 1
      if [ -x "$entry" ]; then chmod +x "$destination/$name" || return 1; fi
    else
      echo "Refusing staged special file: $entry" >&2; return 1
    fi
  done
}
mkdir -p -- "$PARENT"
[ ! -L "$DESTINATION" ] || die "destination became a symbolic link"
if [ -e "$DESTINATION" ]; then
  [ -d "$DESTINATION" ] && [ -z "$(ls -A -- "$DESTINATION")" ] || die "destination is no longer empty"
else
  mkdir -- "$DESTINATION"
fi
# Anchor traversal to this directory even if a parent is renamed during publication.
(cd -P -- "$DESTINATION" && publish_tree "$TARGET" .)
TARGET=$DESTINATION
set +e
CREATED=1

cat <<EOF

Created $TARGET
Environment: $ENV_TEXT, because $REASON.

Next steps:
  1. cd $TARGET
  2. Fill in PROJECT-CHARTER.md. Leave unknown answers as visible open decisions.
EOF
case "$STACK" in
  python) echo "  3. uv init --app .   then   uv add --dev ruff pytest   (review the generated files)" ;;
  rust)   echo "  3. cargo init   (review the generated manifest and add rust-toolchain.toml deliberately)" ;;
  *)      echo "  3. Choose a stack, then replace the placeholders in scripts/check.sh with its commands." ;;
esac
cat <<EOF
  4. Replace the remaining {{...}} placeholders in AGENTS.md; the gate refuses to run
     while its own placeholders remain.
  5. Run $GATE, review 'git status --short --untracked-files=all', then make the first commit.
  6. Create a private GitHub repository when ready:
       gh repo create $NAME --private --source . --remote origin --push
See NEW-PROJECT.md in the toolkit for the full checklist.
EOF
