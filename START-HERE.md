# Start here

This toolkit prepares Windows and, optionally, Fedora in WSL for development. Start with the base environment, then select the stack each project needs. Keep the toolkit separate from project repositories.

## 1. Choose your build environment

Use native Windows for Windows APIs and Windows-only dependencies. Add Fedora in WSL when Linux tools or deployment require it. Linux project checkouts belong inside the WSL filesystem, for example `~/src`; Windows checkouts can live in `C:\src`.

Finish Windows Update and any required restart first. Keep this setup folder at an accessible local path such as `C:\Dev-Setup`; substitute your actual path below.

## 2. Check and prepare Windows

```powershell
cd C:\Dev-Setup
powershell -NoProfile -File .\bootstrap-windows.ps1 -Check
powershell -NoProfile -File .\bootstrap-windows.ps1 -InstallMissing
```

Base tools are Git, GitHub CLI, VS Code and PowerShell 7, plus general editor extensions. GitHub authentication is optional. Open a new terminal after installation and rerun with the same options to pick up PATH changes. If a downloaded script is blocked, inspect it before using `Unblock-File` on that specific file.

Rust, its compiler/linker checks and Cargo tools require explicit [Rust stack selection](docs/stacks/rust.md). Existing tools and settings are retained when switching profiles.

## 3. Add Fedora in WSL if needed

Check existing distributions with `wsl -l -v`, then prove the chosen distribution starts with `wsl -d <Fedora-name> -- true`. A registered distribution with a missing disk is not healthy; see Appendix B of `dev-environment-setup.md` before attempting recovery. Do not unregister it without understanding the data-loss consequences.

For a new WSL installation, enable platform support using `wsl --install --no-distribution` from administrator PowerShell, restart when requested, then use `wsl --list --online` to obtain the Fedora distribution name. Install that exact name with `wsl --install <Fedora-name>`, complete Linux account creation, and verify version 2 and successful startup. Firmware virtualization must be enabled for WSL2.

Inside Fedora:

```bash
cd /mnt/c/Dev-Setup
bash bootstrap-wsl.sh --check
bash bootstrap-wsl.sh
bash bootstrap-wsl.sh --doctor
```

The Fedora base package set is curl, Git and GitHub CLI. VS Code must already be reachable through the Remote-WSL integration for extension installation. Use `--no-dnf` to skip privileged package installation; missing base packages still fail readiness checks.

The optional browser bridge is installed with `--install-browser-bridge`. It requires sudo and reachable Windows PowerShell and cannot be combined with `--no-dnf`. It preserves custom handlers. After successful installation, open a new login shell or run `export BROWSER=/usr/local/bin/wslview` before browser sign-in. Check and doctor modes never install the bridge.

## 4. Select editor settings and a stack

Start with the appropriate General settings in [profiles/](profiles/README.md). Create only the editor profiles you use. For Rust, select the optional [Rust stack](docs/stacks/rust.md) and matching editor settings. Other languages follow the choices in the project charter.

## 5. Optional accounts and agents

Set your Git commit identity separately in each environment using `git config --global user.name` and `git config --global user.email` with your chosen values. Follow each repository’s line-ending policy.

For GitHub access, run `gh auth login --hostname github.com --git-protocol https --web`, then `gh auth status --hostname github.com --active`. Fedora provisioning can set up the Git credential helper after successful authentication; rerun the bootstrap if needed. Do not paste tokens into files or prompts.

Agent installation and sign-in are optional and separate on Windows and Fedora. Follow the agents’ official installation instructions. To opt into this toolkit’s existing agent defaults and MCP configuration, add `-ConfigureAgents` on Windows or `--configure-agents` on Fedora. This creates missing settings, configures Context7, and appends a missing Codex GitHub MCP table after GitHub CLI authentication. Existing settings are preserved; no language commands are automatically allowed in newly created Claude settings. Existing permissions are not rewritten.

Use the corresponding launcher in `helpers/` only when you selected GitHub MCP. It obtains the credential for the agent process without persisting it. Review the scope of connected services before enabling them.

## 6. Verify readiness

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -Doctor
```

```bash
bash bootstrap-wsl.sh --doctor
```

Include the same stack and agent options you selected during installation to check those features. Check/doctor modes do not provision tools or write configuration; Windows doctor may start a registered WSL distribution. Review warnings and [manual checks](doctor/README.md); exit zero is not a guarantee that every optional feature is ready.

## 7. Begin project work

Use [NEW-PROJECT.md](NEW-PROJECT.md) for a new repository. Existing repository documentation and CI define that project’s setup. Optional [project guides](docs/projects/README.md) retain the Nomad, Razer and NCAAM material for users who need it.

For each change: inspect the working tree, create a branch, run the project gate, review the diff and use a pull request. Fix an existing baseline failure before adding new infrastructure.
