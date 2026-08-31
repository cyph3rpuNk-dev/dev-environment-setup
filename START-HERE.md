# Start here

This is the canonical setup guide for a new Windows 11 PC. Follow it from top to bottom the first time. After the machine is working, use the shorter checklists near the end for normal project work.

This setup supports three kinds of work:

1. **Nomad Launcher**, built natively on Windows with the Rust MSVC toolchain.
2. **razer-control-secureblue**, built inside Fedora on WSL2.
3. **New projects**, created from a small, reviewed repository foundation instead of copying assumptions from either existing Rust project.

The setup folder is workstation infrastructure. Keep it separate from your project repositories. Do not copy the whole folder into Nomad Launcher, razer-control-secureblue, or a new repository.

## What each document is for

| File or directory | Use it for |
|---|---|
| `START-HERE.md` | The complete new-PC sequence and the two existing repository workflows. |
| `NEW-PROJECT.md` | Creating a repository from an idea, including the planned NCAAM projection system. |
| `dev-environment-setup.md` | Detailed reasoning and project-specific reference material. It is not the first-run tutorial. |
| `bootstrap-windows.ps1` | Windows installation, configuration, and read-only health checks. |
| `bootstrap-wsl.sh` | Fedora/WSL installation, configuration, and read-only health checks. |
| `profiles/` | Portable VS Code settings for Rust and general Windows/WSL work. |
| `templates/` | Repository policy, project charter, gate, and toolchain starting points. |
| `doctor/` | What the automated health checks can and cannot verify. |
| `helpers/` | Optional Codex launchers for a process-scoped GitHub MCP token. |

## Before you begin

You need:

- A Windows 11 account with administrator access.
- Internet access for Windows Update, WSL, package installation, and GitHub.
- Your GitHub account credentials.
- Your Claude and ChatGPT/OpenAI account credentials if you plan to use both agents.
- The complete contents of this setup folder.

Choose a temporary local location for the setup folder, such as `C:\Dev-Setup`. Nextcloud can hold the long-term copy later, but initial setup should not depend on a cloud-sync client already being configured.

Never paste an API key, password, signing key, or personal access token into a repository, agent prompt, Markdown file, shell profile, or committed configuration.

---

# Part 1: prepare Windows

## Step 0: check what this machine already has

Do not assume a new machine is empty or that a used machine is complete. Check the
starting state before installing anything, and prefer a check that proves a thing
works over one that proves it is merely listed somewhere.

Open PowerShell and run:

```powershell
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
"Windows build      : " + (Get-CimInstance Win32_OperatingSystem).BuildNumber
"Hypervisor present : " + $cs.HypervisorPresent
"Virtualisation     : " + $cpu.VirtualizationFirmwareEnabled
"RAM (GB)           : " + [math]::Round($cs.TotalPhysicalMemory/1GB, 1)
"Free on C: (GB)    : " + [math]::Round((Get-PSDrive C).Free/1GB, 1)
foreach ($c in 'wsl','git','gh','code','rustup','pwsh','php','python','node') {
    $p = (Get-Command $c -ErrorAction SilentlyContinue).Source
    "{0,-8} : {1}" -f $c, $(if ($p) { $p } else { 'not installed' })
}
```

`Virtualisation` must be `True`. If it is `False`, WSL2 cannot run at all: enable
virtualisation (Intel VT-x or AMD-V) in the firmware setup screen before continuing,
because every later step in Part 2 will fail without it. A `VMMonitorModeExtensions`
value of `False` is normal once a hypervisor is already active and is not a fault.

Write down which tools are already present. The bootstrap scripts skip what exists,
but knowing the starting state is what tells you later whether a failure is new or
was already there.

## Step 1: finish the basic Windows setup

1. Complete Windows Setup and sign in.
2. Open **Settings > Windows Update**.
3. Install all available security and cumulative updates.
4. Restart, check again, and repeat until Windows reports no pending restart.
5. Confirm that the system clock and time zone are correct. Authentication and TLS connections can fail when the clock is wrong.

If the device uses BitLocker or another recovery-key system, make sure you know where the recovery key is stored before making major system changes.

## Step 2: install WSL2 and Fedora

A distribution listed by `wsl -l -v` is not necessarily a working one. The
registration and the virtual disk are separate things, and the disk can be missing
while the row still reads `Stopped` and `2`. Prove it starts before deciding to skip
this step:

```powershell
wsl -l -v
wsl -d <Fedora-name> -- true
```

If the second command exits without printing an error, Fedora works and you can go to
Step 3. If it reports `ERROR_PATH_NOT_FOUND` or fails to attach a disk, the
registration is orphaned rather than installed; see "A registered WSL distribution
will not start" in Appendix B of `dev-environment-setup.md` before reinstalling.

Open **PowerShell as Administrator** and run:

```powershell
wsl --install --no-distribution
```

`--no-distribution` enables the platform without also installing Ubuntu, which plain
`wsl --install` does by default. You are choosing Fedora deliberately below.

Restart Windows when requested. Then open PowerShell and list the distributions that your current Windows build offers:

```powershell
wsl --list --online
```

Install the Fedora entry shown by that command. Replace the placeholder, angle
brackets included, with the exact name from the list. The brackets mark a value you
supply; they are not part of the command:

```powershell
wsl --install <Fedora-name-from-the-list>
```

Launch Fedora from the Start menu. Create a Linux username and password when asked. The Linux password is separate from your Windows password and is used by `sudo`.

Confirm the result from PowerShell:

```powershell
wsl -l -v
wsl -d <Fedora-name> -- true
```

The Fedora row should show version `2`, and `Running` and `Stopped` are both normal
states. The second command must also exit without an error: that is what proves the
distribution actually starts rather than merely being registered.

## Step 3: run the Windows bootstrap

Open a normal, non-administrator PowerShell window and change to the setup folder:

```powershell
cd "C:\Dev-Setup"
```

Use the real folder path if you chose a different location.

First run the read-only check:

```powershell
powershell -File .\bootstrap-windows.ps1 -Check
```

If PowerShell says the downloaded script is blocked, inspect the file first. If it is
the expected file from this setup bundle, remove only that file's download mark and
retry:

```powershell
Unblock-File .\bootstrap-windows.ps1
```

Then install the missing base tools, Rust tools, and VS Code extensions:

```powershell
powershell -File .\bootstrap-windows.ps1 -InstallMissing
```

Close PowerShell and open it again after installation so newly installed programs are on `PATH`. PowerShell 7 should now be available as `pwsh`. Run the installer again so it can finish anything skipped during the first process:

```powershell
cd "C:\Dev-Setup"
pwsh -File .\bootstrap-windows.ps1 -InstallMissing
```

The script is designed to be rerun. It does not delete files or touch a project repository. It leaves existing `~/.codex/config.toml` and `~/.claude/settings.json` files alone rather than overwriting them.

### If the MSVC linker check fails

The bootstrap detects a missing Windows linker but does not silently install the large Visual Studio C++ workload. Run:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e
```

In the Visual Studio Installer, select **Desktop development with C++** and complete the installation. Reopen PowerShell and rerun the Windows bootstrap.

Do not continue to the Nomad setup until the script reports that the MSVC linker works.

---

# Part 2: prepare Fedora in WSL

## Step 4: run the Fedora bootstrap

Open Fedora. The Windows setup folder is available through `/mnt/c`. For the example location above:

```bash
cd /mnt/c/Dev-Setup
bash bootstrap-wsl.sh --check
bash bootstrap-wsl.sh
```

Enter the Fedora password when `sudo` asks for it. The script installs the system libraries needed by razer-control-secureblue, Rust tooling, GitHub CLI, and Linux-side VS Code extensions.

Run it a second time after the first installation:

```bash
bash bootstrap-wsl.sh
```

The second run should mostly report that tools are already installed. It also catches items that were not available on `PATH` during the first run.

The script checks for Rust 1.85 or newer because the Razer repository uses Rust edition 2024. The repository may later declare a newer minimum, so its current `Cargo.toml` and CI remain authoritative.

---

# Part 3: install and sign in to the development agents

## Step 5: install Claude Code

Install Claude Code independently on Windows and in Fedora. The two environments have separate executables, settings, and sign-in state.

On Windows PowerShell, the current native installer documented by Anthropic is:

```powershell
irm https://claude.ai/install.ps1 | iex
```

Inside Fedora/WSL:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Verify both installations:

```text
claude --version
claude doctor
```

Installation methods change. If either command above stops matching the official instructions, use <https://code.claude.com/docs/en/installation> rather than an unofficial installer.

In VS Code, install **Claude Code** from publisher **Anthropic**. The extension and CLI serve different entry points, so install both.

## Step 6: install Codex

Install Codex independently on Windows and inside Fedora. Use the current official installation page because the available Windows installers and package managers can change:

<https://learn.chatgpt.com/docs/codex/cli>

The current documented standalone installer for Linux and WSL is:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

After following the Windows tab on the official page, verify both installations:

```text
codex --version
```

In VS Code, install **Codex** from publisher **OpenAI**. Install the extension on the Windows side and in the Remote-WSL window when VS Code offers both locations.

## Step 7: sign in on both sides

On Windows, run:

```powershell
claude
codex
```

Complete each browser sign-in, then exit the session.

Inside Fedora, run the same two commands and sign in again:

```bash
claude
codex
```

Windows sign-in does not sign in the WSL installations.

## Step 8: check the initial agent configuration

The bootstraps create conservative defaults only when the corresponding file does not already exist.

For Codex, the intended baseline is:

```toml
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
```

On native Windows the bootstrap also adds:

```toml
[windows]
sandbox = "elevated"
```

OpenAI documents `elevated` as the recommended native Windows sandbox mode. Use `unelevated` only if administrator-backed sandbox setup is unavailable or fails.

In a Codex session, use `/status` and `/permissions` to confirm the active repository, sandbox, writable roots, and approval behavior before allowing changes.

For Claude Code, open VS Code user settings and set:

- **Initial Permission Mode:** `plan`
- **Preferred Location:** `sidebar`

Use the **User** settings tab. Do not put personal agent defaults in a repository’s workspace settings.

---

# Part 4: configure VS Code profiles

## Step 9: create the four reusable profiles

Create these profiles from VS Code’s profile menu:

| Profile | Purpose | Settings source |
|---|---|---|
| `Rust · Windows` | Nomad Launcher and Windows-native Rust | `profiles/Rust-Windows.settings.jsonc` |
| `Rust · WSL` | razer-control-secureblue and Linux Rust | `profiles/Rust-WSL.settings.jsonc` |
| `General · Windows` | Future Windows-native projects | `profiles/General-Windows.settings.jsonc` |
| `General · WSL` | Future Linux, data, service, and command-line projects | `profiles/General-WSL.settings.jsonc` |

For each profile:

1. Select the profile.
2. Open **Preferences: Open User Settings (JSON)** from the Command Palette.
3. Copy the matching settings template into that profile.
4. Install only the language extensions required by projects using that profile.
5. Export the finished profile to a private backup.

VS Code installs extensions separately on Windows and Remote-WSL. Open a Remote-WSL window, select the WSL profile, and rerun `bash bootstrap-wsl.sh` from its integrated terminal so the Linux-side extension set is installed in the correct host.

Do not commit exported profiles. A repository should recommend extensions through `.vscode/extensions.json`, while personal profile exports stay private.

---

# Part 5: configure Git and GitHub

## Step 10: set your Git identity

Run these commands on Windows and inside Fedora, replacing the placeholders with the name and email you want recorded in commits:

```text
git config --global user.name "<your-name>"
git config --global user.email "<your-github-email>"
git config --global init.defaultBranch main
```

Verify them:

```text
git config --global --list
```

Do not set a global line-ending conversion rule just because a generic tutorial says to. Use each repository’s `.gitattributes` as the source of truth.

## Step 11: authenticate GitHub CLI

Authenticate separately on Windows and inside Fedora:

```text
gh auth login --hostname github.com --git-protocol https --web
gh auth status --hostname github.com --active
```

If you deliberately use an existing fine-grained personal access token instead, use GitHub CLI’s interactive `--with-token` flow. Never place the token in a shell history, repository, Markdown file, or persistent environment variable.

### GitHub MCP is optional

Use ordinary `git` and `gh` commands first. They cover cloning, branches, pull requests, issues, and Actions without adding an MCP server.

If you need GitHub MCP in Codex, rerun the relevant bootstrap after `gh auth status` succeeds, then start Codex with the matching helper:

```powershell
.\helpers\codex-with-github-mcp.ps1
```

```bash
bash ./helpers/codex-with-github-mcp.sh
```

The helper retrieves the token from GitHub CLI and exposes it only to that Codex process.

Claude Code’s documented GitHub MCP method stores a PAT-backed authorization header in Claude’s user-scoped MCP configuration. The bootstraps do not perform that persistent credential write automatically. Configure it manually only after deciding that you need it, use a fine-grained token limited to the required repositories, and rotate or remove it when it is no longer needed. See `dev-environment-setup.md` section 5.8.

---

# Part 6: verify the machine before cloning projects

## Step 12: run both doctor checks

On Windows:

```powershell
cd "C:\Dev-Setup"
pwsh -File .\bootstrap-windows.ps1 -Doctor
```

Inside Fedora:

```bash
cd /mnt/c/Dev-Setup
bash bootstrap-wsl.sh --doctor
```

Then manually verify what the scripts cannot prove:

```text
git --version
gh auth status
rustc --version
cargo --version
claude --version
codex --version
```

Open one Windows VS Code window and one Remote-WSL window. Confirm that each window is using the intended profile and that its extensions show the expected install location.

Do not continue until Git, Rust, VS Code, and the agents start successfully in both environments. GitHub authentication may remain optional if you are not ready to clone or publish repositories.

---

# Part 7: set up Nomad Launcher

Nomad Launcher is a Windows-native repository. Its remote `main` branch is the source of truth. The setup guide is advice written against a dated snapshot and must not override newer repository code, CI, or policy.

## Step 13: clone or update Nomad Launcher

In Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force C:\src | Out-Null
git clone https://github.com/cyph3rpuNk-dev/Nomad-Launcher.git C:\src\Nomad-Launcher
cd C:\src\Nomad-Launcher
git status
```

If the repository is already cloned:

```powershell
cd C:\src\Nomad-Launcher
git status
git fetch origin
git switch main
git pull --ff-only
```

Stop if `git status` reports work you do not recognize. Do not discard it.

## Step 14: prove the current Nomad baseline

Run the checks the repository currently documents before adding setup files:

```powershell
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

If the repository now has a committed `check.ps1`, run that instead and treat it as the canonical gate:

```powershell
pwsh -File .\check.ps1
```

Record pre-existing failures before asking an agent to change anything.

## Step 15: prepare the Nomad foundation on a branch

Create a branch:

```powershell
git switch -c chore/dev-environment-foundation
```

Open this repository in the `Rust · Windows` VS Code profile. Give one agent the setup folder’s `dev-environment-setup.md` as reference without committing that personal guide to the repository. Use this brief:

> Compare the current Nomad Launcher branch with sections 3.4, 4.1, 4.2, 5.2, 5.6, 5.7, and 7.1 of the supplied development-environment guide. Apply only foundation changes that remain valid against the current repository. Treat current code, tests, SPEC.md, SECURITY.md, CI, and release scripts as authoritative. Verify every proposed invariant against code before documenting it. Do not modify `core/src/`, `launchers/`, signing material, or release behavior. Derive any licence allow-list from `cargo deny check`; do not guess it. Keep personal settings and credentials untracked. Run the resulting repository gate, show the full diff, and stop without committing or pushing.

The intended foundation is a committed gate, a deliberate Rust toolchain policy, verified invariants in normal project documentation, a thin `AGENTS.md`, and narrowly unignored `.vscode` files. The agent must skip anything the current repository already implements differently.

Review every changed line before committing. Nomad’s verification, signing, hardening, and cleanup paths are security boundaries, not ordinary refactoring targets.

## Step 16: commit through a pull request

After the gate passes and you approve the diff:

```powershell
git add --all
git diff --staged
git commit -m "chore: add development environment foundation"
git push -u origin chore/dev-environment-foundation
gh pr create --fill
```

Wait for GitHub Actions and review the pull-request diff before merging.

---

# Part 8: set up razer-control-secureblue

razer-control-secureblue is a Fedora/Linux repository. Keep its canonical checkout inside the WSL filesystem, not under `/mnt/c`.

## Step 17: clone or update razer-control-secureblue

Inside Fedora:

```bash
mkdir -p ~/src
git clone https://github.com/cyph3rpuNk-dev/razer-control-secureblue.git ~/src/razer-control-secureblue
cd ~/src/razer-control-secureblue
git status
```

If it is already cloned:

```bash
cd ~/src/razer-control-secureblue
git status
git fetch origin
git switch main
git pull --ff-only
```

Stop if `git status` reports work you do not recognize.

## Step 18: prove the current Razer baseline

Run the repository’s existing gate:

```bash
./scripts/check.sh
```

If it is not executable, inspect it before running `bash scripts/check.sh`. Do not change file permissions until you know whether the repository intended it to be executable.

Record pre-existing failures.

## Step 19: prepare the Razer foundation on a branch

```bash
git switch -c chore/dev-environment-foundation
```

Open the repository from a Remote-WSL window using the `Rust · WSL` profile. Use this brief with one agent:

> Compare the current razer-control-secureblue branch with sections 3.4, 4.1, 4.2, 5.2, 5.5, 5.6, 5.7, and 7.2 of the supplied development-environment guide. Apply only foundation changes that remain valid against the current repository. Preserve the existing `CLAUDE.md` content verbatim when moving shared policy into `AGENTS.md`; do not summarize or regenerate it. Treat current code, tests, CI, and documentation as authoritative. Do not modify `src/`, `desktop/`, or `tray/`, except for a reviewed `rust-version` declaration if current compatibility proves it. Run `cargo deny check` before choosing licences. Do not run a real hardware backend or any command that can write to the embedded controller. Run the final repository gate, show the full diff, and stop without committing or pushing.

Verify that Claude’s hardware guard actually blocks a request to run a hardware-writing command. Codex does not inherit Claude-specific enforcement, so the same prohibition must appear in `AGENTS.md` and command approval must stay enabled.

## Step 20: commit through a pull request

After the gate passes and you approve the diff:

```bash
git add --all
git diff --staged
git commit -m "chore: add development environment foundation"
git push -u origin chore/dev-environment-foundation
gh pr create --fill
```

Wait for GitHub Actions and review the pull-request diff before merging.

---

# Part 9: create a completely new project

Do not clone the assumptions of Nomad Launcher or razer-control-secureblue into an unrelated project. Start with the language-neutral foundation in `templates/`, then add only the files required by the chosen stack.

Use `NEW-PROJECT.md` for the complete process. The short sequence is:

1. Write a one-page project charter before choosing tools.
2. Decide whether the project belongs on Windows or inside WSL.
3. Create the local directory and initialize Git with `main`.
4. Choose the runtime, package manager, licence, and deployment target deliberately.
5. Add a stack-specific `.gitignore` and a committed dependency lockfile.
6. Copy the foundation templates and replace every `{{...}}` placeholder.
7. Create one local gate that formats, lints, tests, and runs project-specific checks.
8. Add CI that calls the same gate.
9. Run the gate locally before the first commit.
10. Create a private GitHub repository first, push `main`, then use branches and pull requests for subsequent work. Make it public only after reviewing licences, credentials, data rights, documentation, and security assumptions.

The planned **NCAAM Team-Total Projection and Reasoning System** should normally start as a data-oriented WSL project unless a Windows-only dependency is identified. Before selecting libraries or data vendors, define:

- What a projection predicts and when the prediction is considered final.
- Which data sources may legally be stored, transformed, and redistributed.
- How teams, seasons, games, and neutral-site status are identified.
- How training data is separated from future information to prevent leakage.
- How forecasts are backtested, calibrated, versioned, and explained.
- Whether the system is research-only or will support real decisions.

`NEW-PROJECT.md` contains a dedicated NCAAM section and a reusable checklist for other future projects whose stack is not yet known.

---

# Part 10: day-to-day workflow

For every repository:

1. Start from an updated `main` with a clean working tree.
2. Create one branch for one coherent change.
3. Let one agent own the task from investigation through a passing gate.
4. Inspect commands before approval and inspect the diff before committing.
5. Run the repository gate yourself.
6. Push the branch and use a pull request, even when working alone on a risky project.
7. Use the other agent for a read-only second opinion when a diff touches an invariant, security boundary, data definition, release process, or migration.

Useful commands:

```text
git status
git diff
git diff --staged
git log --oneline -10
```

Never rely only on an agent’s statement that tests passed. Read the command output or run the gate again yourself.

---

# Part 11: final new-PC checklist

The initial setup is complete when all of these are true:

- Windows Update has no pending restart.
- `wsl -l -v` shows Fedora at version 2, and `wsl -d <Fedora-name> -- true` exits cleanly.
- The Windows bootstrap doctor has no unexplained failures.
- The WSL bootstrap doctor has no unexplained failures.
- The Windows Rust linker probe succeeds.
- VS Code opens both native Windows and Remote-WSL folders.
- The four profiles exist and use the correct settings templates.
- Git identity is configured on Windows and in WSL.
- `gh auth status` succeeds on each side where GitHub access is needed.
- `claude --version`, `claude doctor`, and `codex --version` work on both sides.
- Codex reports `on-request` approvals and a workspace-write sandbox.
- Nomad Launcher is under `C:\src`, has a clean baseline, and builds natively.
- razer-control-secureblue is under `~/src`, has a clean baseline, and passes its gate.
- No token, key, personal profile, or machine-specific user configuration has been committed to either repository.
- Each repository foundation change is reviewed through its own branch and pull request.

When a check fails, stop at that layer. Fix machine setup before repository setup, and fix the existing repository baseline before adding new policy or automation.
