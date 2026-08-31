# Simple setup guide

This is a quick checklist, not the canonical new-PC guide. Use `START-HERE.md` when
setting up a new machine or when a step below fails.

You will create two separate work areas:

- Windows for Nomad Launcher and future Windows-native projects.
- Fedora inside WSL for razer-control-secureblue and future Linux or data projects.

Do one section at a time and verify it before continuing.

## Part 1: Set up Windows

1. Open PowerShell.

2. Go to the folder containing the setup files:

```powershell
cd "C:\Dev-Setup"
```

3. Run:

```powershell
powershell -File .\bootstrap-windows.ps1 -InstallMissing
```

4. Let it finish. If it tells you to install Visual Studio Build Tools, follow the printed instruction and select “Desktop development with C++”.

5. Reopen PowerShell, rerun the bootstrap with `pwsh`, and resolve any linker failure
   by installing Visual Studio Build Tools with the Desktop development with C++
   workload.

6. Install the Claude Code and Codex VS Code extensions from publishers Anthropic and
   OpenAI. Install both command-line tools from their current official setup pages.

7. In PowerShell, run each once and sign in:

```powershell
claude
codex
```

Run `pwsh -File .\bootstrap-windows.ps1 -Doctor` before considering the Windows side
ready.

## Part 2: Set up Fedora in WSL

Skip this part if you already have a working Fedora WSL terminal.

1. Open PowerShell as Administrator.

2. Run:

```powershell
wsl --install --no-distribution
```

Plain `wsl --install` also installs Ubuntu, which you do not want here; you pick
Fedora in step 5.

3. Restart when Windows asks.

4. Open PowerShell again and see the available Linux distributions:

```powershell
wsl --list --online
```

5. Install the Fedora option shown in that list:

```powershell
wsl --install <Fedora-name-from-the-list>
```

6. Open the new Fedora application from the Start menu and create its Linux username and password.

## Part 3: Set up the Linux side

Inside the Fedora terminal, run:

```bash
cd /mnt/c/Dev-Setup
bash bootstrap-wsl.sh
```

Enter your Fedora password if asked.

Then install Claude Code and Codex inside Fedora too, and sign in:

```bash
claude
codex
```

Run `bash bootstrap-wsl.sh --doctor`. Windows and WSL are separate environments, so
their installations, settings, extensions, and sign-ins are separate.

## Part 4: Clone your repositories

You can now clone your repositories.

- Clone Nomad Launcher from a Windows PowerShell terminal into `C:\src\Nomad-Launcher`.
- Clone razer-control-secureblue from the Fedora terminal into `~/src/razer-control-secureblue`.

Use the verified clone commands in `START-HERE.md`. Do not put the Linux repository
under `/mnt/c`.

## Part 5: Open them in VS Code

For Nomad Launcher, open the Windows folder in VS Code.

For razer-control-secureblue, open VS Code, choose “Connect to WSL”, then open `~/src/razer-control-secureblue`.

Create the `Rust · Windows` and `Rust · WSL` profiles from `profiles/`, open each
repository in the matching profile, and run its existing checks before changing files.

## Part 6: Let an AI add repository-specific configuration

Only after the repository opens and its baseline passes, use the project brief in
`START-HERE.md`.

That prompt tells the AI to create a branch, avoid changing source code, prepare the repository configuration, run its checks, and show you the diff. You review the diff before committing anything.

## New projects

Use the `General · Windows` or `General · WSL` profile and follow `NEW-PROJECT.md`.
Start with a project charter, a private GitHub repository, one local gate, and the
smallest end-to-end milestone. Do not copy Nomad or Razer policy into an unrelated
project.

GitHub MCP, optional plugins, custom skills, and advanced agent automation can wait
until a real workflow requires them. Profiles, doctor checks, repository gates, and
secret handling are part of the initial foundation and should not be skipped.
