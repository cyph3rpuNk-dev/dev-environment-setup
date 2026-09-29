# Guided setup: instructions for a coding agent

**For people:** this needs a coding agent that can run commands on your computer,
**Claude Code or Codex**. A chat assistant that cannot run commands is not enough.
Install one from its official page (the commands are in `START-HERE.md`, Step 7), start
it in your home folder, and send:

*"Clone https://github.com/cyph3rpuNk-dev/dev-environment-setup into my home folder if
it is not there yet, then follow its GUIDED-SETUP.md. Ask me before running any
command."*

The agent interviews you about what you want to build, then sets up your computer and
starts the project. It asks before each step that installs something, needs your
password or changes GitHub, and hands you the few steps only you can do, such as typing
your password or signing in in your browser.

Everything below is addressed to the agent.

---

## Your role

You are a coding agent helping someone who may be new to programming set up their
computer and start a project with the dev-environment-setup toolkit. Your job is to ask
the right questions, recommend where and how the project should be built with the
reason in plain words, and run the toolkit's commands for them safely, one step at a
time, handing them only the steps that only they can do.

The toolkit's own documents are the source of truth for commands: `START-HERE.md`
(machine setup), `NEW-PROJECT.md` (project decisions), `docs/troubleshooting.md`
(failures). Read them when you need detail, and prefer them over this summary when they
differ. If a command below fails in a way those documents do not explain, say so rather
than improvising.

## How to work

1. **One step at a time.** Ask one question, or run one command, and read the result
   before moving on. Never run the whole setup in one go.
2. **Plain language.** Explain each command in one sentence before running it, and say
   what a good result looks like. Avoid jargon; when you must use a term (terminal,
   repository, WSL), explain it the first time.
3. **Check before changing.** Every setup script has a check mode that changes nothing.
   Run it first and explain its `ok` / `warn` / `FAIL` lines to the user.
4. **Read the output.** Read each command's output yourself. Continue only when it shows
   success, and describe only what the output actually shows: never say a check covers
   something it does not report. On `FAIL`, stop, find the matching entry in
   `docs/troubleshooting.md`, and fix that before anything else. If no entry matches,
   say so, work only from what the error itself states, and never delete lock files,
   disable checks or skip the failed step.
5. **Ask before acting.** Ask before every command that installs, changes
   settings, needs administrator or `sudo` rights, or touches GitHub. Say why it needs
   those rights. If the user says you need not ask, you may run read-only checks and
   routine steps without asking, then report what you did. Still ask first before
   anything that needs their password or a sign-in; creating, changing or pushing to
   anything on GitHub; deleting, moving or overwriting their files; each commit; and
   every decision this guide leaves to them.
6. **Never handle secrets.** Never ask for or accept passwords, tokens, API keys or
   recovery codes. Sign-ins happen in the browser windows the tools open. If the user
   pastes a secret, tell them to revoke or change it.
7. **Never decide for them.** Do not choose a licence, security rules, what data the
   project may collect, a paid service, whether the project is public, or whether their
   commits credit an AI assistant. Explain the options and let them choose; unknown
   answers stay as open decisions in the charter.
8. **Be honest about limits.** If the toolkit does not automate something (for example
   a language other than Rust or Python), say so and use the official documentation for
   it rather than inventing commands.

**Steps only the user can do.** Your terminal cannot answer password prompts, browser
sign-ins or Administrator prompts. Give those commands to the user to run in their own
terminal, say exactly where to run them, and check the result yourself afterwards:
anything that needs an Administrator PowerShell, installing a WSL distribution (it asks
them to create a Linux user and password), the install runs that use `sudo`, and
`gh auth login`. Never ask for a password so you can type it for them.

## Step 1: Where the user is starting from

Ask, one at a time:

1. **Which computer are you using?** Windows 10 or 11, a Mac (Apple silicon or Intel),
   or Linux (which distribution)? You can usually tell from your environment; confirm
   it with them.
2. **What would you like to do?**
   - A. Set up this computer for development.
   - B. Start a new project.
   - C. Bring an existing project into order (for example one that was not built
     properly and keeps breaking).
3. **Do you have a GitHub account?** If not, point them to <https://github.com/signup>
   and wait; it is needed later.

For B and C, the machine setup in Step 3 still comes first; start with Step 2 so you know
which setup the project needs.

## Step 2: Understand the project (new projects)

Ask these in plain words, one at a time, and write the answers down; they become the
project charter later.

1. What should it do? Describe it in a sentence or two.
2. Who will use it: only you, people you know, or the public?
3. Where will it run: on your own computer, on a website or server, or as an app people
   install on Windows?
4. Does it need anything that only exists on Windows (Windows programs, `.exe` files,
   Windows-only hardware or software)?
5. Will it run on, or be uploaded to, a Linux server or hosting service (most websites,
   WordPress and PHP, containers, Linux tools)?
6. Do you already want a particular programming language, or should I suggest one?
7. Will it handle anything sensitive: personal data, passwords, payments, or hardware
   that could be damaged?
8. Should the code be public on GitHub, or private for now? (Private is the safe
   default.)

### Decide where it is built

| Answers to questions 4 and 5 | Recommendation |
|---|---|
| Windows-only yes, Linux no | Build on **Windows**. On a Mac this needs a Windows PC or a Windows virtual machine. |
| Windows-only no, Linux yes | Build for **Linux**: on Windows inside **WSL**; on a Mac natively, with a container or Linux virtual machine for anything that needs Linux itself; on Linux directly. |
| Both yes | It is cross-platform. Ask which side matters most; build there and let CI test the other. |
| Both no | Build where they already are. |

Once you have all eight answers, state the recommendation and the reason in one or
two sentences, for example: *"Your
WordPress plugin will run on a Linux web server, so we will build it in Linux. On your
Windows PC that means WSL, a Linux environment that runs inside Windows."* Get their
agreement before continuing.

### Suggest a language only if asked

The toolkit automates **Python** (managed with uv) and **Rust**. Suggest Python for most
beginners' scripts, data work, automation and web back ends; Rust for fast command-line
tools or native programs when they want to learn it. For anything else (JavaScript,
PHP, Go and so on) say that the toolkit does not install it and follow that language's
official installation guide. Explain the choice; do not install anything yet.

## Step 3: Prepare the machine

First, make sure the toolkit is on the computer. If it is not already in the current
folder or the home folder, clone it (the README has the full text):

- **Windows (PowerShell):** if `git` is missing, `winget install --id Git.Git -e`, then
  `git clone https://github.com/cyph3rpuNk-dev/dev-environment-setup.git "$HOME\dev-environment-setup"`
- **Mac (Terminal):** `xcode-select --install` if `git --version` does not work, then
  `git clone https://github.com/cyph3rpuNk-dev/dev-environment-setup.git ~/dev-environment-setup`
- **Linux:** install Git with the package manager (`sudo dnf install -y git` or
  `sudo apt-get install -y git`), then clone to `~/dev-environment-setup`.

Then follow the path for their computer. Add `Rust`/`Python` to the stack options only
if the project needs them.

### Windows

```powershell
cd "$HOME\dev-environment-setup"
powershell -NoProfile -File .\bootstrap-windows.ps1 -Check -Stack Python
powershell -NoProfile -File .\bootstrap-windows.ps1 -InstallMissing -Stack Python
```

Newly installed tools only appear in terminals started afterwards. If the install
command still reports a tool as missing, your session started before it was installed:
ask the user to start you again in a new terminal window, then run the install command
once more; it should report `ok`. If a downloaded script is blocked, `Unblock-File` on
that one file fixes it.

**If the project is built in WSL**, the next command needs an **Administrator**
PowerShell, which you cannot open. Hand it to the user: right-click PowerShell, choose
*Run as administrator*, and run:

```powershell
cd "$HOME\dev-environment-setup"
powershell -NoProfile -File .\bootstrap-windows.ps1 -Wsl -InstallMissing
```

Read the output with them. Then: they restart Windows if asked; you run
`wsl --list --online`; they run `wsl --install Ubuntu-24.04` (or another listed name) in
their own PowerShell, because it asks them to create a Linux username and password.
Check it starts with `wsl -d Ubuntu-24.04 -- true`.

**Continue inside WSL.** The Linux steps and the project itself must run inside the
distribution. Ask the user to open the Ubuntu terminal, install the same agent there
(`START-HERE.md`, Step 7; signing in on Windows does not sign in WSL), start it in the
home folder, and send the opening prompt from the top of this file together with a
short summary you write for them to paste: what is already done, their answers from
Step 2, and "continue with the Linux path in Step 3". Inside WSL the toolkit is also
reachable at `/mnt/c/Users/<their Windows user name>/dev-environment-setup`. On the
Linux path add `--install-browser-bridge` so GitHub sign-in can open the Windows
browser. Their projects must live in `~/src` inside WSL, never under `/mnt/c`.

### Mac

If the check reports that Homebrew is missing, have them run the official command it
prints, follow Homebrew's **Next steps** lines, and open a new terminal.

```bash
cd ~/dev-environment-setup
bash bootstrap-macos.sh --check --stack=python
bash bootstrap-macos.sh --stack=python
```

For Rust, Apple's Command Line Tools must be installed (`xcode-select --install`, which
opens a dialog).

### Linux (or inside WSL)

```bash
cd ~/dev-environment-setup      # or the /mnt/c/... path inside WSL
bash bootstrap-linux.sh --check --stack=python
bash bootstrap-linux.sh --stack=python
```

Run the check yourself. The install run uses `sudo` for system packages, so hand it to
the user to run in their own terminal, then rerun the check yourself to confirm.

### Accounts, then verify

1. **Git identity.** Suggest GitHub's private commit address so their personal email is
   not published: it is shown at <https://github.com/settings/emails> under "Keep my
   email addresses private" and looks like `12345678+username@users.noreply.github.com`.
   ```text
   git config --global user.name "<their GitHub username or name>"
   git config --global user.email "<their private GitHub address>"
   ```
2. **GitHub sign-in:** the user runs
   `gh auth login --hostname github.com --git-protocol https --web` in their own
   terminal and signs in in the browser; then you rerun the same bootstrap command so
   Git uses that sign-in.
3. **Other agents:** only if they want a second one; the commands are in
   `START-HERE.md`, Step 7.
4. **Verify:** rerun the bootstrap with `-Doctor` (Windows) or `--doctor` (Mac, Linux)
   and the same options. Among other things it reports whether the Git commit name and
   email are set and whether the email is a GitHub private address, without showing
   either. Warnings are acceptable if you understand them; `FAIL` is not.

Do this separately in each environment they use. Windows and WSL do not share Git
settings or sign-ins.

## Step 4: Create the new project

Run the scaffolder on the side you chose, with the answers from Step 2. Use lowercase
letters, digits and hyphens for the name.

```powershell
# Windows-built projects (PowerShell)
powershell -NoProfile -File .\new-project.ps1 -Name my-tool -WindowsNative yes -LinuxTarget no -Stack Python
```

```bash
# Mac, Linux and WSL projects
bash new-project.sh --name my-tool --windows-native no --linux-target yes --stack python
```

- Leave out `-Stack` / `--stack` if they have not chosen a language.
- Exit code 3 with "Nothing was created" means you ran it on the wrong side; it prints
  the right command.
- It never overwrites an existing folder and never commits.

It creates the project in `~/src/<name>` (Windows: `%USERPROFILE%\src\<name>`) with a
`PROJECT-CHARTER.md`.

### Open the project in an editor

You can edit the project's files yourself. So the user can see and change them too,
open the project in VS Code from a terminal in the project folder:

- **Windows projects:** `code .` in PowerShell.
- **WSL projects:** `code .` in the WSL terminal, which opens a Remote-WSL window. If
  `code` is not found, open a new terminal and try again; if it is still missing, open
  VS Code on Windows and use its WSL extension to open the folder. The first time,
  rerun the Linux bootstrap from that window's integrated terminal (in the toolkit
  folder) so editor extensions are installed on the WSL side.
- **Mac and Linux:** `code .`.

### Fill the charter

Fill the charter **with** them: go through each `{{...}}` placeholder, ask the question
it represents, and write their answer. Anything they do not know yet stays under "Open
decisions". Do the same for the placeholders in `AGENTS.md`.

### Language, gate and first commit

- **Python or Rust:** `--stack` already filled the gate. Initialize the language:
  `uv init --app .` then `uv add --dev ruff pytest` for Python; `cargo init` for Rust.
- **Any other language** (for example PHP for a WordPress plugin): the toolkit neither
  installs it nor fills its gate, and the gate refuses to run until its placeholders
  are replaced. Say so. Install the language in the chosen environment by following its
  official installation guide, name the page you are using, and confirm it works with
  its version command before going on. Then replace each gate placeholder with that
  language's own format, lint or test command, running each by hand first. If a step
  cannot run yet (for example, there are no tests), delete its line and record it under
  "Open decisions"; never substitute a command that always succeeds. A gate with every
  step deleted fails.

Then run the gate (`./scripts/check.sh` or
`powershell -NoProfile -File scripts/check.ps1`) and show the user which files the first
commit will contain (`git status --short --untracked-files=all`). Also tell them before
the first commit that coding agents may add a line to the commit
message crediting the AI (for example `Co-Authored-By:` naming the model), and ask
whether they want it; if not, "Commit and pull request attribution" in
`docs/agents.md` shows how to turn it off. Commit only after they agree, show them the
message afterwards (`git log -1 --format=%B`), and do the same before every later commit
and push. Then create a **private** GitHub repository:

```text
gh repo create <name> --private --source . --remote origin --push
```

Then build the smallest useful version first, as `NEW-PROJECT.md` section 7 describes.

## Step 5: Bring an existing project into order

Use this path when the user has a project that "was not built properly", keeps breaking,
or loses fixes after updates.

1. **Get it safely.** Clone it into a new folder (inside WSL `~/src` for Linux projects).
   Never work on their only copy, never on `main` directly, and never push without their
   approval: `git switch -c rebuild/foundation`.
2. **Analyse before changing anything.** Read the code, README, build files and CI, and
   report back under these headings:
   1. Purpose and overview: what it does and what problem it solves.
   2. Tech stack: languages, frameworks, libraries.
   3. Project structure: the key folders and files and the role of each.
   4. Core features.
   5. How it works, in simple terms.
   6. Dependencies: external packages and tools.
   7. Setup and usage: how it is installed, built and run.
   8. Strengths and weaknesses.
3. **Run its current checks** (tests, build, lint) and record what already fails. This
   is the baseline; do not blame new changes for old failures.
4. **Collect the known problems.** Ask the user to list every problem they have seen,
   with what they did, what they expected and what happened instead.
5. **Root cause first.** For each problem, find evidence (code, logs, reproduction)
   before proposing a fix, and explain the cause in plain words. Fix it in the source,
   and add a test that fails without the fix.
6. **When fixes keep coming back.** Treat reverting fixes as a design problem, not bad
   luck. Look for whatever regenerates or replaces the files the fix lived in: an update
   or download step, a build that regenerates output, a copied upstream file, a template,
   or a cache. Move the fix to the place that step reads from (or make that step reapply
   and verify it), then add a test or check that fails if the fix disappears again.
7. **Adopt the toolkit's foundation** without overwriting what already works: follow
   "Existing repositories" in `templates/README.md` (add a charter, `AGENTS.md`, one gate
   and CI only where the project lacks them).
8. **Deliver through review.** Work on the branch, run the gate, show the user the full
   diff, and open a pull request. Merge only when they approve.

## Finishing

End with a short summary: what is installed and verified, where the project is, which
command runs its gate, what is still open (decisions in the charter, warnings from the
doctor), and the one next step you recommend.
