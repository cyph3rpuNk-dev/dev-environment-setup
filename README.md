# Development environment setup

**[New to coding with AI? Start here.](docs/vibe-coder-project-guide.md)** A plain-language guide to turning your idea into a project with a coding agent.

Prepare your computer and start a software project with a clear foundation. This
toolkit helps beginners and experienced developers install development tools,
choose a working environment, and create project folders with documented goals,
coding-agent instructions, and local checks. Follow the guides yourself or work
through them with a coding agent on **Windows**, **macOS**, **Linux**, or **WSL**.

## Choose your starting point

| I want to… | Start here |
|---|---|
| Understand how to build with an AI coding agent | [Beginner project guide](docs/vibe-coder-project-guide.md) |
| Prepare my computer for development | [START-HERE.md](START-HERE.md) |
| Plan and create a new project | [NEW-PROJECT.md](NEW-PROJECT.md) |
| Have an agent walk me through setup or improving an existing project | [GUIDED-SETUP.md](GUIDED-SETUP.md) |

## What the toolkit does

It does three things:

1. **Prepares the machine.** Git, GitHub CLI, VS Code extensions and, only when you
   select them, language stacks (Rust, Python/uv), a WSL environment and AI coding
   agent defaults. Check and doctor modes report without changing anything.
2. **Helps you choose where a project lives.** Use Windows for Windows-only tools
   and dependencies. For projects deployed to Linux, the toolkit recommends Linux
   or WSL on Windows to keep development close to deployment. Many web projects
   can also be developed on Windows or macOS; the right choice depends on their
   dependencies. On a Mac, develop natively and use containers or a Linux virtual
   machine for Linux-only requirements.
3. **Starts new repositories from a reviewed foundation.** A project charter, shared
   agent policy (`AGENTS.md`, optional `CLAUDE.md`), local check scripts ready to
   connect to continuous integration (CI), and
   sensible Git defaults. Undecided choices stay visible instead of being guessed.

The scaffolder creates the project's foundation. You still need to initialize the
chosen language, fill in project decisions, build application code, add meaningful
tests, and configure CI. A **gate** is the command that runs the project's required
checks, such as formatting, linting, and tests. Stack-specific gates need the
corresponding project tools; a gate with unresolved placeholders refuses to run.

## Get the toolkit

You need Git to clone. Keep the toolkit outside your project repositories.

**Windows** (PowerShell):

Cloning needs no administrator rights. Installing Git may prompt for administrator
approval.

```powershell
winget install --id Git.Git -e          # skip if 'git --version' already works
# open a new PowerShell window so git is on PATH, then:
git clone https://github.com/cyph3rpuNk-dev/dev-environment-setup.git "$HOME\dev-environment-setup"
cd "$HOME\dev-environment-setup"
```

**macOS** (Terminal):

```bash
xcode-select --install         # Apple's Command Line Tools, which include git; skip if 'git --version' works
git clone https://github.com/cyph3rpuNk-dev/dev-environment-setup.git ~/dev-environment-setup
cd ~/dev-environment-setup
```

**Linux** (Fedora/RHEL or Debian/Ubuntu):

```bash
sudo dnf install -y git        # Fedora/RHEL
sudo apt-get install -y git    # Debian/Ubuntu
git clone https://github.com/cyph3rpuNk-dev/dev-environment-setup.git ~/dev-environment-setup
cd ~/dev-environment-setup
```

Without Git, use GitHub's **Code > Download ZIP** and extract it to the same place.
Files extracted from a downloaded ZIP can be marked as blocked. `bootstrap-windows.ps1`
loads `helpers\github-auth.ps1`, so inspect both files, then unblock both, for example
`Unblock-File .\bootstrap-windows.ps1, .\helpers\github-auth.ps1`.

## Quick start

Full, explained steps are in [START-HERE.md](START-HERE.md). The short version:

| You are on | Run | Add a stack |
|---|---|---|
| Windows | `powershell -NoProfile -File .\bootstrap-windows.ps1 -Check`, then `powershell -NoProfile -File .\bootstrap-windows.ps1 -InstallMissing` | `-Stack Rust,Python` |
| macOS | `bash bootstrap-macos.sh --check`, then `bash bootstrap-macos.sh` (needs [Homebrew](https://brew.sh)) | `--stack=rust,python` |
| Linux | `bash bootstrap-linux.sh --check`, then `bash bootstrap-linux.sh` | `--stack=rust,python` |
| Windows, Linux-targeted project | Windows steps with `-Wsl` added (Administrator PowerShell), then inside WSL the Linux steps | as above |

Then start a project:

```powershell
powershell -NoProfile -File .\new-project.ps1        # Windows-native projects
```

```bash
bash new-project.sh                                  # macOS, Linux or WSL projects
```

The scaffolder asks whether the project is a native Windows program and whether it
targets Linux, recommends where it belongs and says why. If you run it on the wrong
side, it creates nothing and prints the command for the right one.

## Let a coding agent set it up

New to this? Let a coding agent do the work. You need **Claude Code or Codex**; install
one from its official page (commands in [START-HERE.md](START-HERE.md), Step 7), start it
in your home folder, and send:

> Clone https://github.com/cyph3rpuNk-dev/dev-environment-setup into my home folder if
> it is not there yet, then follow its GUIDED-SETUP.md. Ask me before running any
> command.

It asks what you want to build, recommends where to build it and why, sets up your
computer, and creates the project; it can also bring an existing project into order.
It asks before each step that installs something, needs your password or changes
GitHub, and hands you the steps only you can do, such as typing your password or
signing in in your browser. [GUIDED-SETUP.md](GUIDED-SETUP.md) holds its instructions.
The guided workflow has previously been tested with Claude Code. Codex has been
used for repository maintenance and offline validation; a complete guided setup
on a fresh machine with Codex has not yet been verified.

## What it never does

- Uninstall software, overwrite existing agent or editor settings, or replace a custom
  browser handler.
- Store a GitHub token in a file, shell profile or persistent environment variable.
- Install a WSL distribution, Homebrew or Apple's Command Line Tools for you, select the
  Visual Studio C++ workload, or decide a project's licence, security rules or
  supported platforms. It prints the official command instead.
- Pin tool versions. It installs the current official releases (rustup and uv from
  their install scripts, winget, Homebrew, apt and dnf packages, VS Code extensions), so
  a later run can install newer versions than an earlier one.

## Layout

| Path | Purpose |
|---|---|
| [Beginner project guide](docs/vibe-coder-project-guide.md) | Plain-language workflow and starting prompts for building with a coding agent |
| [START-HERE.md](START-HERE.md) | Guided machine setup for Windows, macOS, Linux, and Windows + WSL |
| [GUIDED-SETUP.md](GUIDED-SETUP.md) | Instructions that let a coding agent (Claude Code or Codex) interview you and do the setup |
| [NEW-PROJECT.md](NEW-PROJECT.md) | Turning an idea into a repository; what the scaffolder creates and what you still decide |
| `bootstrap-windows.ps1`, `bootstrap-linux.sh` | Rerunnable setup with `-Check`/`--check` and `-Doctor`/`--doctor` modes; the Linux script also handles macOS |
| `bootstrap-macos.sh` | macOS entry point; runs `bootstrap-linux.sh` |
| `bootstrap-wsl.sh` | Older name for `bootstrap-linux.sh`; still works |
| `new-project.ps1`, `new-project.sh` | Project scaffolder |
| [docs/stacks/](docs/stacks/README.md) | Optional Rust and Python stacks |
| [docs/agents.md](docs/agents.md) | Claude Code and Codex: shared policy, enforcement, MCP, review habits |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Failures that actually happen and what they mean |
| [profiles/](profiles/README.md) | VS Code settings templates |
| [templates/](templates/README.md) | Repository foundation templates used by the scaffolder |
| [doctor/](doctor/README.md) | What the automated checks can and cannot prove |
| `helpers/` | Browser bridge for WSL sign-in; GitHub auth checks; WSL drive-location helper; retired-launcher migration notices |

## Maintaining this toolkit

Run the offline gate from the toolkit folder:

```powershell
powershell -NoProfile -File scripts/check.ps1
# Or, on PowerShell 7 (Windows or Linux):
pwsh -NoProfile -File scripts/check.ps1
```

Use an absolute script path when outside this repository. The gate requires Git,
PowerShell 5.1+ and Bash; it uses Git for Windows Bash when installed in its standard
location. It checks PowerShell/Bash syntax, profile and embedded Claude JSON,
credential lifetime, gate and placeholder failures, browser input handling,
linker-probe failures, WSL enablement decisions, the scaffolder, and mocked
first-run/rerun/doctor behavior on Fedora, Debian/Ubuntu, native Linux, WSL and
macOS fixtures. Tests use temporary fixtures and fake credentials. They do not install
software or access real agent accounts. ShellCheck and PSScriptAnalyzer run when
installed; the analyzer uses `PSScriptAnalyzerSettings.psd1`.

CI runs on pull requests, on pushes to `main`, and on manual dispatch. It runs the same
gate with Windows PowerShell 5.1, Windows PowerShell 7, Linux PowerShell 7 and macOS
PowerShell 7 (with macOS's Bash 3.2), with PSScriptAnalyzer pinned on Linux, and runs
ShellCheck and the Bash tests inside Fedora and Debian containers. These tests
do not prove that winget, Homebrew, distribution packages, WSL enablement or live authentication
work on a fresh machine. Use the doctor and manual checks for those boundaries.

CI also checks that every commit is authored by the maintainer and carries no
co-author, session-link or bot credit (`scripts/check-commit-identity.sh`), and
`.claude/settings.json` switches off Claude Code's commit and pull request
attribution in this repository.

The shared maintenance policy is [AGENTS.md](AGENTS.md). [CLAUDE.md](CLAUDE.md)
imports that policy rather than keeping a second copy.

## License

MIT. See [LICENSE](LICENSE).
