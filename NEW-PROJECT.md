# New project playbook

Use this guide when a project does not exist yet. Its purpose is to turn an idea into a small, reproducible repository without pretending that unknown requirements have already been decided.

The development-environment folder remains outside the new repository. Copy only the templates that become part of the project’s reviewed foundation.

## Fast path: the scaffolder

`new-project.ps1` (Windows) and `new-project.sh` (macOS, Linux or WSL) perform sections 1, 2
and the mechanical part of 5 below:

```powershell
powershell -NoProfile -File .\new-project.ps1 -Name my-tool
```

```bash
bash new-project.sh --name my-tool
```

They ask whether the project is a native Windows program and whether it runs on or
deploys to Linux, recommend an environment with the reason, and record both in the
charter. In a new or empty directory they create `README.md`, `PROJECT-CHARTER.md`,
`AGENTS.md`, `CLAUDE.md` (skip with `-NoClaude`/`--no-claude`), `scripts/check.*`,
`.gitattributes`, `.gitignore` and `.editorconfig`, and initialize Git on `main`. They
never commit and never overwrite. Run on the wrong side, they create nothing and print
the command for the right one.

Files and Git metadata are prepared in a separate staging directory first. Symlink
and junction destinations are rejected. If preparation fails, the destination is
untouched. A publication conflict stops without recursively deleting destination
contents. On Bash, files already published before a late conflict remain for review;
inspect them before retrying. Failed staging directories are retained at the printed
path for inspection and manual removal. Avoid concurrent writers to the destination;
this tool does not isolate it from hostile processes running as the same user.

`-Stack Rust|Python` / `--stack rust|python` fills the gate with that stack's usual
format, lint and test commands. Choose it only when you have decided the stack; without
it the gate keeps its placeholders and refuses to run until you replace them.

Everything the scaffolder cannot know stays a visible `{{...}}` placeholder. The rest
of this guide explains how to decide those answers.

## Rule zero: define the project before choosing a stack

Create a short project charter first. Start from `templates/foundation/PROJECT-CHARTER.md.template` and answer these questions:

- What problem does the project solve?
- Who will use it?
- What is the smallest useful result?
- What inputs does it accept and what outputs does it produce?
- What data, credentials, devices, or external systems can it access?
- What must never happen?
- How will you prove that a change is correct?
- Where will it run?
- Does it need to be public, or should it begin as a private repository?

Unknown answers should stay marked as decisions to make. Do not let an agent silently fill them with plausible guesses.

## 1. Choose the execution environment

Use one primary environment per project.

| Choose | When it is the better fit |
|---|---|
| Native Windows | The product calls Windows APIs, builds Windows executables, uses MSVC, signs PE files, automates Windows applications, or depends on Windows-only hardware or SDKs. |
| Linux (WSL on a Windows machine) | The product is a Linux service, web application or site (including WordPress and other PHP), containerized workload, Linux command-line tool, or will deploy to Linux. Data and Python projects usually fit here too because their tooling and deployment targets are Linux-first. |
| Both, with one canonical side | The project has a real cross-platform requirement. Pick one canonical development side and make the other a CI or compatibility target. |

On a Linux machine, "Linux" simply means the machine itself. On a Windows machine it
means a WSL distribution (`bootstrap-windows.ps1 -Wsl`, see START-HERE.md Part 1,
Step 3). On a Mac, Linux-targeted projects are developed natively, because macOS is
Unix-like; use a container or Linux virtual machine for anything that needs Linux
itself. A native Windows program cannot be built on a Mac; use a Windows PC or a
Windows virtual machine. Do not keep an active Linux checkout under `/mnt/c`; store it under `~/src`
inside WSL. Do not build a Windows-native project from WSL merely because WSL is
available.

If the environment choice is still unclear, write a small proof-of-concept outside the final repository and decide after testing the uncertain dependency.

## 2. Name the project and create its directory

The scaffolder does this step for you. To do it by hand, choose a short repository name containing lowercase letters, numbers, and hyphens. Avoid embedding a temporary implementation choice in the name unless that choice is part of the product.

On Windows:

```powershell
New-Item -ItemType Directory -Force "$HOME\src\<project-name>" | Out-Null
Set-Location "$HOME\src\<project-name>"
git init -b main
```

Inside WSL:

```bash
mkdir -p ~/src/<project-name>
cd ~/src/<project-name>
git init -b main
```

Confirm the location before creating files:

```text
git status
```

## 3. Record the first decisions

Copy `templates/foundation/PROJECT-CHARTER.md.template` to `PROJECT-CHARTER.md` and replace every placeholder you can answer.

At minimum, decide or explicitly defer:

- Project purpose and non-goals.
- Public, private, local-only, or undecided visibility.
- Runtime and supported operating systems.
- Language and minimum supported version.
- Package manager and dependency lockfile.
- Licence and ownership.
- Data classification and retention.
- Deployment target.
- Local validation command.
- CI provider.

Do not select an open-source licence by habit. If ownership, third-party code, model weights, or dataset rights are unclear, keep the repository private and mark the licence decision unresolved.

## 4. Select a stack deliberately

Choose the smallest stack that can deliver the first milestone. Verify the current official documentation for the selected runtime and package manager before writing installation commands.

Record:

- The exact runtime or toolchain policy.
- How dependencies are added and locked.
- How formatting runs.
- How linting and static analysis run.
- How tests run.
- How the application starts locally.
- How production artifacts are built.

Commit the lockfile for applications and reproducible analysis projects unless the chosen ecosystem has a documented reason not to.

Do not install every possible language globally on the new PC. Install a runtime when a real project selects it: the toolkit's Rust and Python (uv) stacks are in [docs/stacks/](docs/stacks/README.md); for anything else follow the runtime's official guidance and add its extension to the project's `.vscode/extensions.json`.

## 5. Add the repository foundation

The normal starting set is:

```text
<project>/
├── README.md
├── PROJECT-CHARTER.md
├── AGENTS.md
├── CLAUDE.md
├── LICENSE                 # only after the licence is decided
├── .gitignore
├── .gitattributes
├── .vscode/
│   ├── extensions.json
│   └── settings.json
├── .editorconfig
├── scripts/
│   └── check.*             # .ps1 on Windows or .sh on Linux
├── tests/
└── <stack-owned files>
```

Add only files the project needs. An empty directory tree is not architecture.

### README.md

The first README should state:

- What the project is.
- Its current maturity.
- How to install dependencies.
- How to run it.
- How to run the complete local gate.
- Where design and security decisions live.

Do not claim features that have not been implemented.

### .gitignore and .gitattributes

Build `.gitignore` from the chosen stack’s actual output and secret files. Review every rule. A broad rule can hide configuration that should have been committed.

Use `.gitattributes` to make line endings and binary files explicit. Prefer repository policy over a global Git line-ending setting.

Before the first commit, run:

```text
git status --short --untracked-files=all
```

Every untracked path should be either intentionally committed or intentionally ignored.

### Agent policy

Copy `templates/foundation/AGENTS.md.template` to `AGENTS.md`. Replace every placeholder with a verified fact or an explicitly unresolved decision.

Copy `templates/foundation/CLAUDE.md.template` only if Claude Code will be used. Keep shared policy in `AGENTS.md`; use `CLAUDE.md` only as the import adapter and for Claude-specific operations.

Do not ask an agent to invent:

- Security invariants.
- Supported platforms.
- Data rights.
- Minimum runtime versions.
- Licence allow-lists.
- Release credentials.
- Destructive or production commands.

### One local gate

Copy the applicable gate template:

- `templates/foundation/check.ps1.template` for Windows.
- `templates/foundation/check.sh.template` for Linux or WSL.

Replace the formatting, linting, and test placeholders with commands already selected for the project. For a language the toolkit does not automate (anything other than Rust or Python), use that language's own tools, installed from its official documentation. If a step cannot run yet, for example because there are no tests, delete its line and record it under "Open decisions" in the charter. Never substitute a command that always succeeds; the gate refuses to pass when every step has been deleted. Add security, schema, data, documentation, packaging, or integration checks only when their inputs and failure policy are defined.

The gate must:

- Run from the repository root.
- Return zero only when all required checks pass.
- Be safe to run repeatedly.
- Avoid production writes, real purchases, hardware writes, and destructive migrations.
- Match CI.

Run every individual command first. Add it to the combined gate only after it works by itself.

## 6. Separate secrets, data, and generated artifacts

Never commit live credentials. Use an ignored local environment file only when the stack requires it, and commit a redacted example such as `.env.example` containing names but no values.

Classify project inputs:

| Class | Typical handling |
|---|---|
| Small source fixtures | Commit when redistribution is allowed and tests need them. |
| Large public datasets | Download through a reproducible script; record source, version, and checksum. |
| Licensed or private datasets | Keep outside Git; document access and retention without publishing the data. |
| Generated outputs | Rebuild from source when practical; ignore them unless releases require committed artifacts. |
| Secrets | Keep in a credential manager, CI secret store, or approved local secret mechanism. |

An ignored file is not automatically safe. It can still leak through logs, screenshots, shell history, notebooks, copied error messages, or agent context.

## 7. Build the first vertical slice

The first milestone should exercise the full path with the smallest possible input:

1. Read or accept one representative input.
2. Validate it.
3. Produce one useful output.
4. Test the behavior.
5. Run it through the local gate and CI.

Prefer synthetic or public fixture data for this slice. Do not begin by importing the largest production dataset or automating the most dangerous external action.

## 8. Add CI

Create CI only after the local gate passes. CI should invoke the same gate or the same underlying commands, not create a second definition of correctness.

Use minimal permissions, pin runtime versions deliberately, cache only safe build inputs, and never print secrets. Add a job for every platform the project actually promises to support.

If CI cannot run an essential check, document the manual release or hardware verification step and who is responsible for it.

## 9. Create the GitHub repository

Begin privately unless public visibility is already a deliberate requirement.

1. Create an empty repository on GitHub. Do not ask GitHub to add a README, licence, or `.gitignore` because the local repository already owns those files.
2. Copy the remote URL.
3. Connect and push:

```text
git add --all
git diff --staged
git commit -m "chore: establish project foundation"
git remote add origin https://github.com/<owner>/<project-name>.git
git push -u origin main
```

Verify the GitHub file list. Confirm that no secret, private dataset, local environment, or editor profile was published.

After the initial foundation, use a branch and pull request for each coherent change:

```text
git switch -c <type>/<short-description>
```

## 10. First agent session

Ask the agent to inspect before editing:

> Read `PROJECT-CHARTER.md`, `AGENTS.md`, the dependency manifest, the local gate, and CI. Report any contradiction or unresolved placeholder before changing files. Work only on the requested first milestone. Do not select a licence, external data source, runtime minimum, security invariant, or deployment target on my behalf. Run the gate, show the diff, and stop without committing or pushing.

Review the result as if it came from another contributor. Agent-generated policy is still a project change that needs human approval.

---

# Reusable readiness checklist

A new project is ready for feature work when:

- The charter states purpose, users, first milestone, non-goals, and safety boundaries.
- The canonical environment is chosen.
- The runtime, package manager, and version policy are recorded.
- The repository has no unresolved template placeholder outside an explicitly marked decision log.
- Secrets and private data are excluded and handled deliberately.
- `AGENTS.md` contains verified project policy.
- One local gate passes from a clean checkout.
- CI runs the same required checks.
- The README describes only implemented behavior.
- The initial GitHub repository has been inspected for accidental disclosure.
- The next change will happen on a branch, not directly on `main`.

If one of these is unknown, keep it visible. An explicit unresolved decision is safer than an invented foundation.
