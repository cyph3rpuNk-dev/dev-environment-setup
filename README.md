# Development environment setup

A workstation toolkit for starting and building software projects on **Windows**,
**macOS** or **Linux**, with an optional **WSL** Linux environment for Windows users
whose project targets Linux. Clone it onto the machine you use, run the bootstrap
for that operating system, then create each new project with the scaffolder.

It does three things:

1. **Prepares the machine.** Git, GitHub CLI, VS Code extensions and, only when you
   select them, language stacks (Rust, Python/uv), a WSL environment and AI coding
   agent defaults. Check and doctor modes report without changing anything.
2. **Helps you choose where a project lives.** A native Windows program belongs on
   Windows. Anything that runs on or deploys to Linux (web servers, WordPress/PHP,
   containers, Linux services) belongs on Linux, which on a Windows machine means WSL
   and on a Mac means developing natively with containers for Linux-only parts.
3. **Starts new repositories from a reviewed foundation.** A project charter, shared
   agent policy (`AGENTS.md`, `CLAUDE.md`), one local gate that CI also runs, and
   sensible Git defaults. Undecided choices stay visible instead of being guessed.

## Get the toolkit

You need Git to clone. Keep the toolkit outside your project repositories.

**Windows** (PowerShell, no administrator needed):

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
If Windows reports a downloaded script as blocked, inspect it, then run
`Unblock-File` on that file only.

## Quick start

Full, explained steps are in [START-HERE.md](START-HERE.md). The short version:

| You are on | Run | Add a stack |
|---|---|---|
| Windows | `powershell -NoProfile -File .\bootstrap-windows.ps1 -Check`, then `-InstallMissing` | `-Stack Rust,Python` |
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

## What it never does

- Uninstall software, overwrite existing agent or editor settings, or replace a custom
  browser handler.
- Store a GitHub token in a file, shell profile or persistent environment variable.
- Install a WSL distribution, Homebrew or Apple's Command Line Tools for you, select the
  Visual Studio C++ workload, or decide a project's licence, security rules or
  supported platforms. It prints the official command instead.

## Layout

| Path | Purpose |
|---|---|
| [START-HERE.md](START-HERE.md) | Guided machine setup for Windows, Linux, and Windows + WSL |
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
| `helpers/` | Browser bridge for WSL sign-in; Codex launcher with a process-scoped GitHub token |

## Maintaining this toolkit

Run the offline gate from any directory:

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
software or access real agent accounts.

CI runs the same gate with Windows PowerShell 5.1, Windows PowerShell 7, Linux
PowerShell 7 and macOS PowerShell 7 (with macOS's Bash 3.2), and runs the Bash tests
inside Fedora and Debian containers. These tests
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
