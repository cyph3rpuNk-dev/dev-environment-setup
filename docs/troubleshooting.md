# Troubleshooting

The failures that actually happen, and what each one means. Most of them point
somewhere other than their cause.

## Windows

### A downloaded script is blocked

Windows marks files downloaded from the internet, and files extracted from a downloaded
ZIP can keep that mark. `bootstrap-windows.ps1` and `helpers\codex-with-github-mcp.ps1`
both load `helpers\github-auth.ps1`, so inspect the script you run and that helper,
then remove the mark from those files only:

```powershell
Unblock-File .\bootstrap-windows.ps1, .\helpers\github-auth.ps1
```

If the helper is still blocked, the bootstrap reports `GitHub sign-in was not checked:
could not load ...github-auth.ps1` and prints the `Unblock-File` command for that file.
Do not change the machine-wide execution policy to work around it.

### A tool was installed but is "not recognized"

winget updated `PATH` for new processes only. Open a new terminal and rerun the
bootstrap with the same options.

### `cargo build` fails at the linking step

The MSVC C++ build tools are missing. Install
`winget install --id Microsoft.VisualStudio.2022.BuildTools -e` and select
**Desktop development with C++**. `-Stack Rust` provisioning runs a linker probe
precisely because Rust's error does not say this.

### `claude` is not a recognised command

The VS Code extension carries a private copy of Claude Code and does not put `claude`
on `PATH`. Install the standalone CLI (START-HERE.md, Step 7), then open a new
terminal. The same applies inside WSL.

## WSL

### WSL will not enable, or `wsl` is missing

WSL 2 needs Windows 10 version 2004 or later (or Windows 11) and CPU virtualisation
enabled in firmware. `bootstrap-windows.ps1 -Wsl -Check` reports the virtualisation
state. Enabling the platform needs an Administrator PowerShell and usually a restart.

### A registered WSL distribution will not start

`wsl -l -v` lists the distribution as `Stopped` and version `2`, but any command fails
with `Failed to attach disk ... ext4.vhdx` and
`Wsl/Service/CreateInstance/MountDisk/HCS/ERROR_PATH_NOT_FOUND`.

The registration and its virtual disk are separate. An interrupted install or a
cleanup of `%LocalAppData%` can leave a registration pointing at a disk that no longer
exists. Confirm it:

```powershell
wsl -l -v
Get-ChildItem "$env:LOCALAPPDATA" -Recurse -Filter ext4.vhdx -ErrorAction SilentlyContinue
```

Only when there is no matching `ext4.vhdx` is it an orphaned registration, which you
can clear and reinstall:

```powershell
wsl --unregister <Distro-name>
wsl --install <Distro-name>
```

`wsl --unregister` normally deletes the distribution and every file in it
permanently, with no confirmation prompt and no recycle bin. Check the disk listing
and the exact name before running it. This is why the doctor probes with
`wsl -d <name> -- true` instead of trusting the listing.

### Builds are painfully slow in WSL

The project is probably under `/mnt/c`. Files there cross a translation layer on every
access. Move the checkout to `~/src` on the Linux filesystem; this is usually the whole
explanation.

### `bad interpreter: /usr/bin/env bash^M`

The script was checked out with Windows line endings. This repository and projects
from the scaffolder pin LF in `.gitattributes`; if you copied files by other means,
re-clone or run `git add --renormalize .` in the affected repository.

### `gh auth login --web` seems to hang in WSL

WSL has no browser. Install the bridge with
`bash bootstrap-linux.sh --install-browser-bridge`, then open a new login shell or run
`export BROWSER=/usr/local/bin/wslview`. Alternatively copy the printed code and URL to
a Windows browser yourself.

## macOS

### "Homebrew is required" although you installed it

On Apple silicon Homebrew lives in `/opt/homebrew`, which new terminals only find after
the installer's **Next steps** commands add it to your shell profile. The bootstrap finds
it anyway and prints the command to run; after running it, open a new terminal.

### `xcode-select: note: install requested` or a dialog appears

Apple's Command Line Tools are installing. Finish the dialog, then rerun the bootstrap.
Rust needs them to link programs.

### `code` is not found after installing VS Code

Open VS Code, press Cmd+Shift+P, and run **Shell Command: Install 'code' command in
PATH**. Homebrew's VS Code install adds it automatically; a manual install does not.

## Linux and GitHub

### Package installation fails with "Could not get lock"

apt allows one installer at a time. On a newly installed Ubuntu, including a new WSL
distribution, automatic security updates can run during the first minutes, and the
error names the process holding the lock (for example `unattended-upgr`). Wait a
few minutes for it to finish, then rerun the same bootstrap command. Do not delete the
lock files: apt itself warns that removing them can break the system. If the named
process is an install you started yourself in another terminal, let it finish first.

### `git push` over HTTPS stalls with no output

Git is waiting on a username prompt that never renders. After `gh auth login`, rerun
`bash bootstrap-linux.sh` (or run `gh auth setup-git --hostname github.com`) so Git
uses GitHub CLI's credentials.

### A push is rejected because of the `workflow` scope

Pushing files under `.github/workflows` needs a scope a default login omits:
`gh auth refresh --hostname github.com --scopes workflow`.

### "GitHub CLI is not authenticated" although you logged in

Older distribution builds of `gh` may not know `--active`. Both bootstraps support
these builds, but cannot verify the active account's workflow scope without the flag.
The Linux bootstrap detects this and warns; install a current
build from <https://github.com/cli/cli/blob/trunk/docs/install_linux.md>.

### `cargo` or `uv` is not found after installing

The installers add their directories to your shell profile, which takes effect in new
terminals. Open one, or run `. "$HOME/.cargo/env"` / `. "$HOME/.local/bin/env"`.

### Unsupported distribution

`bootstrap-linux.sh` automates dnf and apt. On other distributions it checks tools by
command name; install what it reports with your package manager and rerun.

If a RHEL-family system has no `dnf` (for example Amazon Linux 2), it also falls back
to command checks. On dnf systems, GitHub CLI is installed separately so a missing
`gh` repository does not prevent installing curl, Git or compiler packages. Follow
[GitHub's RPM installation instructions](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
for your package-manager version, then rerun; the toolkit does not add repositories.

## Agents and editors

### rust-analyzer (or any language server) does nothing in WSL

The extension is installed on the Windows side only. In the Remote-WSL window's
Extensions view, installed extensions are grouped by host; code-running extensions
must appear under the WSL group. Rerun `bash bootstrap-linux.sh` from that window's
terminal.

### An MCP server shows "Failed to connect"

For GitHub, first run `gh auth status --hostname github.com --active`. Claude's stored
header is separate from GitHub CLI and is not refreshed by the bootstrap; replace it
manually. For Codex, launch through `helpers/codex-with-github-mcp.*`. For any server,
`claude mcp get <name>` gives more detail than `list`.

### An agent ignores a rule

First confirm it loaded (`/context` in Claude Code; ask Codex what `AGENTS.md` says).
If it loaded and is still ignored, the rule is probably vague or contradicted
elsewhere. Instruction files are guidance; anything that must hold belongs in an
enforced control. Codex never reads `.claude/rules/` or Claude hooks, so a rule that
matters to both must be in `AGENTS.md`. See [agents.md](agents.md).

### A hook does not block anything

Usually the script is not executable, its parser (often `jq`) is missing, or the path
in `.claude/settings.json` does not resolve. A hook that fails to run does not error;
it just does not block. Run it by hand with a sample JSON payload on stdin.
