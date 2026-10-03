# Start here

For an overview of building with a coding agent, read the [vibe coder project guide](docs/vibe-coder-project-guide.md). Return here for the detailed machine setup steps.

This guide takes a machine from nothing to ready for project work. Follow it top to
bottom the first time. Each step says what to run, what a good result looks like, and
what to do when it is not.

Pick your path:

| Your machine | Your project | Follow |
|---|---|---|
| Windows | Windows programs, or no Linux requirement | Part 1, then Part 3 |
| Linux | anything | Part 2, then Part 3 |
| Mac | anything that runs on macOS or Linux (web, Python, Rust, containers) | Part 2b, then Part 3 |
| Mac | a native Windows program | a Windows PC or Windows virtual machine, then Part 1 |
| Windows | runs on or deploys to Linux (web server, WordPress/PHP, containers, Linux tools) | Part 1, Part 2 inside WSL, then Part 3 |

Not sure which kind of project you have? `new-project.ps1` and `new-project.sh` ask two
questions and recommend one; [NEW-PROJECT.md](NEW-PROJECT.md) explains the reasoning.
You can add WSL later; nothing in Part 1 depends on it.

Prefer to have it done for you? A coding agent (Claude Code or Codex) can run these
steps for you, asking before each change; see "Let a coding agent set it up" in
[README.md](README.md). It follows [GUIDED-SETUP.md](GUIDED-SETUP.md).

## Before you begin

You need:

- An account on the machine. Windows needs administrator access only to enable WSL;
  Linux needs `sudo` for system packages.
- Internet access, a GitHub account, and (optionally) Claude and/or OpenAI accounts
  for the coding agents.
- The toolkit itself; see "Get the toolkit" in [README.md](README.md).

Never paste an API key, password, signing key or personal access token into a
repository, agent prompt, Markdown file, shell profile or committed configuration.

Finish operating-system updates and any pending restart first. On Windows, if the
device uses BitLocker, know where the recovery key is before enabling WSL.

---

# Part 1: Windows

## Step 1: check what the machine already has

Open a normal PowerShell window in the toolkit folder:

```powershell
cd "$HOME\dev-environment-setup"
powershell -NoProfile -File .\bootstrap-windows.ps1 -Check
```

Add `-Wsl` if you will need Linux, and `-Stack Rust` or `-Stack Python` (or
`-Stack Rust,Python`) for the languages you already know you need. Check mode changes
nothing. It prints the Windows build, memory and free disk space, then every tool as
`ok`, `warn` or `FAIL`. Note what already exists: that is how you later tell a new
failure from an old one.

With `-Wsl`, `FAIL ... virtualisation is disabled` means WSL 2 cannot run until you
enable Intel VT-x or AMD-V in the firmware (BIOS/UEFI) setup screen.

## Step 2: install the base tools

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -InstallMissing
```

This installs VS Code, Git, GitHub CLI and PowerShell 7 with winget, plus general
editor extensions. Close PowerShell and open a new window so the new programs are on
`PATH`, then run the same command again: the second run finishes anything the first
process could not see yet. Supply the same `-Stack`/`-Wsl` options on every run,
including check and doctor; selections are not remembered.

### Rust on Windows

With `-Stack Rust` the script also installs rustup, rustfmt, clippy and Cargo tools,
then compiles a tiny throwaway crate to prove the MSVC linker works. If that probe
fails:

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e
```

In the Visual Studio Installer select **Desktop development with C++**, finish, open
a new PowerShell and rerun. Do not start Rust project work until the probe passes.
Details: [docs/stacks/rust.md](docs/stacks/rust.md).

## Step 3 (optional): add a Linux environment with WSL

Do this when a project targets Linux. Open **PowerShell as Administrator**:

```powershell
cd "$HOME\dev-environment-setup"
powershell -NoProfile -File .\bootstrap-windows.ps1 -Wsl -InstallMissing
```

The script enables the WSL platform (`wsl --install --no-distribution`) but does not
choose a Linux distribution for you. Restart Windows if asked, then list and install
one:

```powershell
wsl --list --online
wsl --install <Name-from-the-list>
```

Ubuntu (for example `Ubuntu-24.04`) is the most widely documented choice; a
`FedoraLinux-*` entry is equally supported by this toolkit. Replace the placeholder,
angle brackets included. When the distribution opens, create a Linux username and
password; the password is used by `sudo` and is separate from your Windows password.

Prove it actually starts. A distribution that is merely listed can still be broken:

```powershell
wsl -l -v                       # the row should show version 2
wsl -d <Name> -- true           # must return without an error
powershell -NoProfile -File .\bootstrap-windows.ps1 -Wsl -Doctor
```

If the probe reports a failure to attach a disk (`ERROR_PATH_NOT_FOUND`), read
"A registered WSL distribution will not start" in
[docs/troubleshooting.md](docs/troubleshooting.md) before changing anything. Never
unregister a distribution you have not confirmed is empty.

Now continue with **Part 2 inside the WSL terminal**. The toolkit you cloned on
Windows is visible there, so you do not need a second copy:

```bash
cd /mnt/c/Users/<you>/dev-environment-setup
```

Keep Linux **projects** on the Linux filesystem (for example `~/src`), never under
`/mnt/c`: builds there are several times slower and lose Linux file permissions.
Running the toolkit's scripts from `/mnt/c` is fine. If `/etc/wsl.conf` moves the
Windows drives (`[automount]` `root`), the scaffolder's and doctor's location checks
follow that setting, and the browser bridge finds `powershell.exe` on PATH.

---

# Part 2: Linux (native or inside WSL)

## Step 4: check, then install

```bash
bash bootstrap-linux.sh --check
bash bootstrap-linux.sh
```

The script detects whether it is running natively or inside WSL, and uses `dnf`
(Fedora/RHEL) or `apt` (Debian/Ubuntu). It installs curl, Git and GitHub CLI with
`sudo`, plus general VS Code extensions. Add `--stack=rust`, `--stack=python` or
`--stack=rust,python` as needed. Run it a second time; the second run should mostly
report `ok`.

- `--no-sudo` skips system packages and reports them as failures instead.
- Other distributions are detected and checked by command name; install the reported
  packages yourself.
- If it warns that GitHub CLI lacks `--active` (older distribution builds),
  install a current build from GitHub's official instructions it links to.

**VS Code on Linux.** On native Linux install VS Code from
<https://code.visualstudio.com/docs/setup/linux>. Inside WSL, use the Windows VS Code:
run `code .` from the WSL terminal, which opens a Remote-WSL window. Extensions that
run code must be installed on the WSL side, so rerun `bash bootstrap-linux.sh` from that
window's integrated terminal.

**WSL only: browser sign-in.** WSL has no browser of its own, so `gh auth login --web`
appears to hang. Install the small bridge that opens sign-in pages in your Windows
browser (it needs `sudo` and preserves any existing custom handler):

```bash
bash bootstrap-linux.sh --install-browser-bridge
export BROWSER=/usr/local/bin/wslview      # or open a new login shell
```

If `wslview` already exists elsewhere on PATH (for example from the distribution's
`wslu` package), the bootstrap reports it as working, installs nothing and uses no
`sudo`. If sign-in pages still do not open, run `export BROWSER=<that path>` as it
suggests. An existing `xdg-open` anywhere on PATH is left in place,
including its support for opening local files.

---

# Part 2b: macOS

## Step 4b: Command Line Tools and Homebrew

Apple's Command Line Tools provide Git and the compilers everything else needs, and
[Homebrew](https://brew.sh) installs the remaining tools. If they are missing, the
bootstrap stops and prints the official commands. Install them yourself; both ask for
your Mac password and may open a system dialog:

```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

When the installer finishes, its **Next steps** section lists the commands that add
Homebrew to your `PATH`. Run them, then open a new terminal. The bootstrap still finds
Homebrew if you skip this, and warns you until it is on your `PATH`.

## Step 4c: check, then install

```bash
cd ~/dev-environment-setup
bash bootstrap-macos.sh --check
bash bootstrap-macos.sh
```

This installs Git and GitHub CLI with Homebrew (no `sudo`), VS Code if it is missing,
and the general VS Code extensions. Add `--stack=rust`, `--stack=python` or
`--stack=rust,python` as needed. Run it a second time; the second run should mostly
report `ok`.

**Linux-targeted projects on a Mac.** macOS is Unix-like, so most web, Python and Rust
work runs natively. When a project needs Linux itself (Linux-only packages, systemd,
matching a Linux server exactly), use a container tool or a Linux virtual machine for
those parts. The toolkit does not choose one for you: Docker Desktop has licence terms
for larger companies, and OrbStack, Colima and UTM are common alternatives.

---

# Part 3: every machine

Windows and each WSL distribution are separate environments. Do the steps below once
per environment you use: identities, sign-ins, extensions and settings are not shared.

## Step 5: set your Git identity

```text
git config --global user.name "<your-name>"
git config --global user.email "<your-github-email>"
git config --global init.defaultBranch main
git config --global --list
```

Do not set a global line-ending rule from a generic tutorial. Each repository's
`.gitattributes` decides, and projects from the scaffolder get one.

## Step 6: sign in to GitHub

```text
gh auth login --hostname github.com --git-protocol https --web
gh auth status --hostname github.com --active
```

Then rerun the bootstrap for this environment. On Linux it configures Git to use
GitHub CLI's credentials; without that, `git push` over HTTPS waits on a username
prompt that never appears, which looks like a network hang.

If you will push repositories containing `.github/workflows`, add the scope a default
login omits; otherwise GitHub rejects the push:

```text
gh auth refresh --hostname github.com --scopes workflow
```

## Step 7 (optional): install the coding agents

Install each agent in every environment where you will use it. Commands below were
checked against the official pages on 28 September 2026; if they differ now, follow
the official page.

| Agent | Windows PowerShell | macOS, Linux and WSL | Official page |
|---|---|---|---|
| Claude Code | `irm https://claude.ai/install.ps1 \| iex` | `curl -fsSL https://claude.ai/install.sh \| bash` | <https://code.claude.com/docs/en/setup> |
| Codex CLI | `powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 \| iex"` | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | <https://github.com/openai/codex> |

These are vendor-provided streaming installation commands, a deliberate exception
to the bootstrap scripts' download-completely-before-execution rule. To follow the
same rule manually, save the official installer to a private temporary file, check
that the download succeeded, inspect it, then run it with the indicated interpreter.
Never execute a partial or failed download.

Open a new terminal, confirm with `claude --version` / `claude doctor` and
`codex --version`, then run `claude` and `codex` once each to sign in. Signing in on
Windows does not sign in WSL. In VS Code, install **Claude Code** (publisher Anthropic)
and **Codex** (publisher OpenAI); the extension does not put the CLI on `PATH`.

To apply this toolkit's conservative agent defaults (Codex asks at permission
boundaries, while routine workspace commands can run without approval; Claude's file tools are denied `.env` files, common key files and the SSH and
GPG folders, as a safeguard rather than a complete barrier; Context7 documentation server),
rerun the bootstrap with `-ConfigureAgents` or `--configure-agents`. Existing settings
files are never overwritten. [docs/agents.md](docs/agents.md) explains the choices,
GitHub MCP, and how to keep one policy for both agents.

## Step 8: editor profiles

Create only the VS Code profiles you need and paste the matching settings template
from [profiles/](profiles/README.md): `General · Windows`, `General · Linux` (for WSL
windows and native Linux), `General · macOS`, and the Rust variants if you selected
Rust.

## Step 9: verify

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -Doctor      # plus the same -Stack/-Wsl/-ConfigureAgents
```

```bash
bash bootstrap-linux.sh --doctor                                   # Linux or WSL, plus the same --stack/--configure-agents
bash bootstrap-macos.sh --doctor                                   # macOS, plus the same options
```

Doctor modes never install or write configuration; the Windows doctor may start your
WSL distribution to prove it works. Exit code zero means no required failures, not
that every optional feature is ready: read the warnings and the manual checks in
[doctor/README.md](doctor/README.md).

## Ready checklist

- Operating-system updates done, no pending restart.
- Doctor reports no unexplained failures in each environment you use.
- With Rust on Windows: the linker probe passed.
- With WSL: `wsl -d <Name> -- true` succeeds, and Linux projects will live under `~/src`.
- On macOS: Homebrew works in a new terminal, and with Rust the Command Line Tools are installed.
- Git identity set and `gh auth status` succeeds wherever you will push.
- Agents, if used, report a version and are signed in on each side.
- No token, key or personal profile has been committed anywhere.

When a check fails, stop at that layer: fix the machine before the repository, and an
existing project's failing baseline before adding new tooling.

## Next: start or join a project

- New project: `new-project.ps1` (Windows) or `new-project.sh` (macOS, Linux or WSL), then
  [NEW-PROJECT.md](NEW-PROJECT.md).
- Existing project: clone it on the side its README requires, run its own gate first,
  and record pre-existing failures before changing anything.

For every change: start from an updated `main`, one branch per coherent change, one
agent per task and working tree, run the gate yourself, review the diff, and merge
through a pull request. Never rely only on an agent's statement that tests passed.
