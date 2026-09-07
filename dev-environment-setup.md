# VS Code + Claude Code + Codex: a working setup for Nomad Launcher and razer-control-secureblue

Written 19 August 2026. Operational setup, Codex configuration, credential handling,
and reusable-project guidance were revised on 28 August 2026. Repository facts below
remain snapshots at the named commits and must be checked against current `main` before
any change is applied.

Repos analysed:

- `cyph3rpuNk-dev/Nomad-Launcher` at `3923022` (chore(release): v1.0.7)
- `cyph3rpuNk-dev/razer-control-secureblue` at `f6908a7` (docs: link the memory repo README)
- `addyosmani/agent-skills` at HEAD on the date above

Assumptions you confirmed: Windows 11 host with a WSL2 Fedora shell and WSLg, both agents used at full capability with one agent owning a task from start to finish, and you want the config files inline so you can paste them.

## How to use this document

This is a reference, not a tutorial you read front to back. Three ways in:

- **Setting up a machine from scratch?** Start with `START-HERE.md` and the two
  bootstrap scripts.
- **Creating a new project?** Start with `NEW-PROJECT.md` and the language-neutral
  templates. Do not copy either existing project's assumptions.
- **Want to understand a decision?** Sections 1 and 5 carry the reasoning. Everything else is configuration.
- **Want to copy a file?** Sections 3.4, 4, 5.3, 5.4, and 5.6 hold every config file, complete and ready to paste.

Unfamiliar with a term such as *MCP*, *hook*, *skill*, *permission mode*, or *golden bytes*? Appendix A defines all of them in plain language. Something not working? Appendix B lists the failures that actually happen and what each one means.

File paths in headings tell you where a block belongs. Recheck version-sensitive
commands against the current official documentation before automating them.

## Implementation update: reusable foundation

The companion files now implement the following decisions. This section supersedes
earlier examples that save `GITHUB_MCP_PAT` in a user environment variable or
`~/.bashrc`, and earlier wording that implied Claude's PAT-backed MCP header was
process-only.

| Concern | Canonical approach |
|---|---|
| GitHub access and MCP credentials | Use ordinary `git` and `gh` first. The bootstraps check GitHub CLI authentication but never read its token. Codex's optional helper retrieves the token only for the child process. Claude's documented GitHub MCP command stores a PAT-backed header in user-scoped MCP configuration, so the bootstrap leaves that as an explicit manual choice. |
| Cross-agent policy | `AGENTS.md` is the committed canonical policy. `CLAUDE.md` starts with `@AGENTS.md` and contains only Claude-specific adapter material. A critical rule appears in `AGENTS.md` even when Claude additionally enforces it with a hook or deny rule. |
| Reusable vs. project-specific configuration | `templates/` holds foundation and Rust templates with explicit placeholders. The supplied Nomad and razer sections remain project playbooks; do not copy their commands, licences, or invariants into unrelated repositories. |
| Health checks | `bootstrap-windows.ps1 -Doctor` and `bootstrap-wsl.sh --doctor` are read-only checks. `doctor/README.md` records their scope and the manual checks they intentionally cannot prove. |
| VS Code | Create the two Rust profiles for the existing repositories and the two General profiles for future projects. Exported profiles are private backups; the small settings templates are the portable source of truth. |

Do not place a PAT in a shell profile or persistent user environment. A process-scoped
environment variable is used only by the optional Codex helper. Claude's PAT-backed
GitHub MCP configuration has a different persistence model and is described accurately
in section 5.8.

## Contents

- [How to use this document](#how-to-use-this-document)
- [0. Before you start](#0-before-you-start)
  - [0.1 What this document assumes exists](#01-what-this-document-assumes-exists)
  - [0.2 Manual identity and reviewed setup](#02-manual-identity-and-reviewed-setup)
  - [0.3 Where the setup files live](#03-where-the-setup-files-live)
- [1. What the two repos actually demand](#1-what-the-two-repos-actually-demand)
- [2. Machine layout: one box, two build worlds](#2-machine-layout-one-box-two-build-worlds)
- [3. VS Code baseline](#3-vs-code-baseline)
  - [3.1 Use Profiles, not one giant config](#31-use-profiles-not-one-giant-config)
  - [3.2 Extensions](#32-extensions)
  - [3.3 User settings](#33-user-settings)
  - [3.4 Per-repo `.vscode/`](#34-per-repo-vscode)
- [4. Toolchain and cargo tooling](#4-toolchain-and-cargo-tooling)
  - [4.1 Declare the toolchain policy in both repos](#41-declare-the-toolchain-policy-in-both-repos)
  - [4.2 Cargo tools worth having on both sides](#42-cargo-tools-worth-having-on-both-sides)
- [5. The agent layer](#5-the-agent-layer)
  - [5.1 Division of labour: one agent owns a task end to end](#51-division-of-labour-one-agent-owns-a-task-end-to-end)
  - [5.2 Instruction files: one source of truth, two readers](#52-instruction-files-one-source-of-truth-two-readers)
  - [5.3 Claude Code configuration](#53-claude-code-configuration)
  - [5.4 Codex configuration](#54-codex-configuration)
  - [5.5 Skills: write once, serve both agents](#55-skills-write-once-serve-both-agents)
  - [5.6 Hooks: turn conventions into enforcement](#56-hooks-turn-conventions-into-enforcement)
  - [5.7 The same protection, on the Codex side](#57-the-same-protection-on-the-codex-side)
  - [5.8 MCP servers: keep the surface small](#58-mcp-servers-keep-the-surface-small)
  - [5.9 The optional second-opinion pass](#59-the-optional-second-opinion-pass)
  - [5.10 Parallel work with worktrees](#510-parallel-work-with-worktrees)
- [6. `addyosmani/agent-skills`: worth it, with edits](#6-addyosmaniagent-skills-worth-it-with-edits)
- [7. Per-repo playbooks](#7-per-repo-playbooks)
  - [7.1 Nomad Launcher](#71-nomad-launcher)
  - [7.2 razer-control-secureblue](#72-razer-control-secureblue)
- [8. The reusable baseline](#8-the-reusable-baseline)
  - [8.1 Foundation components](#81-foundation-components)
  - [8.2 Setup order for a new machine](#82-setup-order-for-a-new-machine)
  - [8.3 Habits that matter more than configuration](#83-habits-that-matter-more-than-configuration)
- [9. Verify the setup actually works](#9-verify-the-setup-actually-works)
  - [9.1 The editor agrees with the gate](#91-the-editor-agrees-with-the-gate)
  - [9.2 The right extensions are on the right side](#92-the-right-extensions-are-on-the-right-side)
  - [9.3 The MCP servers are connected, not merely configured](#93-the-mcp-servers-are-connected-not-merely-configured)
  - [9.4 The guardrails actually block](#94-the-guardrails-actually-block)
  - [9.5 Both agents can see their instructions](#95-both-agents-can-see-their-instructions)
  - [9.6 A file-by-file checklist](#96-a-file-by-file-checklist)
- [10. What to re-verify, and when](#10-what-to-re-verify-and-when)
- [Appendix A: glossary](#appendix-a-glossary)
- [Appendix B: troubleshooting](#appendix-b-troubleshooting)
  - [rust-analyzer does nothing](#rust-analyzer-does-nothing)
  - [Builds are painfully slow in WSL](#builds-are-painfully-slow-in-wsl)
  - [A registered WSL distribution will not start](#a-registered-wsl-distribution-will-not-start)
  - [`cargo build` fails at the linking step on Windows](#cargo-build-fails-at-the-linking-step-on-windows)
  - [The GTK app launches but the window is blank](#the-gtk-app-launches-but-the-window-is-blank)
  - [A hook does not block anything](#a-hook-does-not-block-anything)
  - [`claude` is not a recognised command](#claude-is-not-a-recognised-command)
  - [An MCP server shows "Failed to connect"](#an-mcp-server-shows-failed-to-connect)
  - [Claude ignores something in CLAUDE.md](#claude-ignores-something-in-claudemd)
  - [Codex ignores a rule that Claude follows](#codex-ignores-a-rule-that-claude-follows)
  - [The razer desktop crate will not compile in WSL](#the-razer-desktop-crate-will-not-compile-in-wsl)
  - [`cargo deny check` fails on a licence you did not add](#cargo-deny-check-fails-on-a-licence-you-did-not-add)
- [Sources](#sources)

---

## 0. Before you start

### 0.1 What this document assumes exists

| Requirement | Why | Where it comes from |
|---|---|---|
| Windows 11 with WSL2 and a Fedora distro | razer builds on Linux, Nomad builds on Windows | `START-HERE.md` parts 1 and 2 |
| VS Code | The editor everything below configures | `bootstrap-windows.ps1` |
| Rust via rustup, on both sides | Both projects are Cargo workspaces | both bootstrap scripts |
| MSVC C++ build tools on Windows | Rust cannot link a Windows binary without them | `bootstrap-windows.ps1` tests this |
| GTK4 and libadwaita dev packages in WSL | The razer desktop crate will not compile without them | `bootstrap-wsl.sh` |
| `claude` and `codex` CLIs, signed in, on both sides | Section 5 configures both | installed by hand, see `START-HERE.md` |
| A git identity | Otherwise your first commit fails with a confusing error | you, see 0.2 |

If you ran both bootstrap scripts and followed `START-HERE.md`, all but the last are already true.

### 0.2 Manual identity and reviewed setup

The scripts deliberately leave account sign-in, Git identity, VS Code profile creation,
agent CLI installation, and the Visual Studio C++ workload to the reviewed steps in
`START-HERE.md`.

Set your Git identity once per side. Windows and WSL are separate environments:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
```

Do not apply a global line-ending setting from a generic tutorial. Both repositories
have `.gitattributes`; let repository policy control their checked-out files.

### 0.3 Where the setup files live

- `START-HERE.md`: canonical new-PC and existing-repository workflow. Keep it.
- `NEW-PROJECT.md`: reusable workflow for projects that do not exist yet.
- `bootstrap-windows.ps1` and `bootstrap-wsl.sh`: rerunnable machine setup.
- `profiles/`, `templates/`, `doctor/`, and `helpers/`: reusable companion material.
- **This document**: dated project analysis and detailed reasoning. Keep it in the
  setup folder. Do not commit the whole personal guide to either product repository;
  copy only reviewed, project-owned policy and configuration.

---

## 1. What the two repos actually demand

Reading both trees, the environment is not really "a Rust setup". It is two Rust setups with opposite constraints, sharing one machine.

**Nomad Launcher** is a Windows-only Cargo workspace: one `nomad-core` library plus nine thin launcher binaries under `launchers/*`, edition 2021, `rust-version = "1.77"`. It links `windows-sys` and `winreg`, builds with `-C control-flow-guard=yes` and `/DEPENDENTLOADFLAG:0x800` from `.cargo/config.toml`, embeds icons via `winresource` build scripts, and ships through `dist.ps1` (PowerShell, `signtool.exe`, SHA256SUMS, offline GPG signing). CI is `windows-latest` for fmt/clippy/test plus an `ubuntu-latest` `cargo audit` job with three documented RUSTSEC ignores. Release builds deliberately skip the cargo cache to avoid cache poisoning, and use Sigstore build attestation. Security posture is the product, so the tooling has to make "did this change weaken a verification path" a visible question.

**razer-control-secureblue** is a Linux-target Cargo workspace (root crate plus `desktop/` and `tray/`), edition 2024, `#![forbid(unsafe_code)]` on every crate, GPL-2.0-only. The desktop client is GTK4 + libadwaita 0.7 (`v1_4` features), the tray is `ksni`, the daemon uses systemd socket activation and `listenfd`, and the real hardware path sits behind both a `hidraw-backend` cargo feature and a runtime `--backend hidraw` flag. The wire encoder is pinned by golden-byte tests. There is a documented cross-platform rule: core and daemon logic must still build on your Windows box, with GTK/ksni gated by `cfg(target_os = "linux")` / `cfg(unix)`.

Three things follow immediately, before any extension list.

**A. Your CI does not enforce the Windows rule.** `razer-control-secureblue/.github/workflows/ci.yml` runs `ubuntu-latest` and a `fedora:latest` container. Nothing checks that the workspace still builds on Windows, even though `CLAUDE.md` states it as a hard convention. That is a gate you are currently enforcing by hand, which means an agent can break it silently. Fix in section 7.2.

**B. Neither repo pins a toolchain.** No `rust-toolchain.toml` in either tree. razer uses edition 2024 (needs Rust 1.85 or newer) but declares no `rust-version`; Nomad declares `rust-version = "1.77"` but nothing verifies MSRV. Two agents, two shells, and a Fedora `dnf`-installed rustc will drift. Fix in section 4.

**C. The two repos disagree about committing agent config.** Nomad's `.gitignore` excludes `.claude/`, `.vscode/`, `CLAUDE.md` and `AUDIT.md`; razer commits `CLAUDE.md` and exactly one skill (`.claude/skills/run-desktop-ui/`) while ignoring the rest of `.claude/`. That is a deliberate split and this guide respects it: Nomad gets untracked local config, razer gets committed config. Section 5.2 covers how to keep both agents fed either way.

---

## 2. Machine layout: one box, two build worlds

Do not try to make one VS Code window serve both projects. The toolchains, the language server's `cfg` view, and the debuggers are all different.

```
Windows 11
├── VS Code (window A)  ── profile "Rust · Windows"
│     C:\src\Nomad-Launcher            ← native MSVC build, PowerShell, signtool
│     C:\src\razer-windows-check       ← second clone, cross-build check only
│
└── VS Code (window B)  ── Remote-WSL into Fedora, profile "Rust · WSL"
      ~/src/razer-control-secureblue   ← canonical checkout, GTK4 build, WSLg UI
```

Rules that matter:

**Keep the razer checkout inside the WSL filesystem** (`~/src/...`), never under `/mnt/c/`. Cargo on a 9p mount is several times slower, and the repo's `.gitattributes` (`* text=auto eol=lf`) plus symlink-based skill sharing behave correctly only on the Linux side.

**The Windows razer clone is a checker, not a workspace.** Its only job is `cargo check --workspace` to prove the cross-platform rule holds. Give it its own target dir so it never contends with the WSL build. Once you add the CI job from 7.2, this becomes optional.

**Install extensions twice.** In a Remote-WSL window, anything that runs code (rust-analyzer, CodeLLDB, the Claude Code extension, the Codex extension, shellcheck) must be installed *in the WSL host*, not on Windows. The `.vscode/extensions.json` files below make VS Code prompt for the right set per folder.

**Install both agent CLIs on both sides.** `claude` and `codex` on Windows for Nomad, and again inside the Fedora WSL distro for razer. They keep separate `~/.claude/` and `~/.codex/` state, so section 5 gives you both copies of each config.

---

## 3. VS Code baseline

### 3.1 Use Profiles, not one giant config

VS Code Profiles (`File > Preferences > Profiles`, or the gear menu) let you carry a distinct extension set and settings per context. Create two:

- **Rust · Windows**: rust-analyzer, PowerShell, C/C++ (for the MSVC debugger), Hex Editor, the agent extensions.
- **Rust · WSL**: rust-analyzer, CodeLLDB, shell/systemd/RPM tooling, the agent extensions.

These profiles are mandatory for the two build worlds in this setup. Seed them from
the matching files in `profiles/`, then export each settled profile for your private
backup. VS Code owns the export format, so the small settings templates, not an
opaque exported profile, are the portable source of truth.

### 3.2 Extensions

Core, both profiles:

| Extension | ID | Why, for these repos specifically |
|---|---|---|
| rust-analyzer | `rust-lang.rust-analyzer` | The only thing that understands `cfg(windows)` vs `cfg(target_os = "linux")` gating and feature flags. Configuration in 3.3 is what makes it match your clippy gates. |
| Error Lens | `usernamehw.errorlens` | Inline diagnostics. With `-D warnings` gates in both repos, seeing clippy output at the line saves a round trip. |
| GitLens | `eamodio.gitlens` | Blame on `src/protocol.rs` golden bytes and on `core/src/hardening.rs` is genuinely load-bearing when you are auditing why a byte changed. |
| GitHub Pull Requests | `github.vscode-pull-request-github` | razer's history is PR-merge based (`Merge pull request #15 …`); review in-editor. |
| GitHub Actions | `github.vscode-github-actions` | Both repos have non-trivial workflows (pinned SHAs, `permissions: {}`, attestation). Schema validation catches typos before a push. |
| TOML support | `tamasfe.even-better-toml` or `tombi-toml.tombi` | `Cargo.toml`, `.cargo/config.toml`, `~/.codex/config.toml`. Even Better TOML is the long-standing one; Tombi is the newer formatter/linter/LSP. Either works; pick one. |
| Dependi | `fill-labs.dependi` | Shows outdated/vulnerable crate versions inline in `Cargo.toml`. Given your `cargo audit` ignore list, seeing version drift early matters. |
| YAML | `redhat.vscode-yaml` | Workflow and BlueBuild recipe editing. |
| Code Spell Checker | `streetsidesoftware.code-spell-checker` | Both repos are documentation-heavy and user-facing. |
| Todo Tree | `gruntfuggly.todo-tree` | Cheap index of the "deferred to post-v1" / "not yet verified" markers you already leave in prose. |
| Markdown Mermaid | `bierner.markdown-mermaid` | For SPEC.md / DEVICES.md diagrams if you add them. |

Windows profile only:

| Extension | ID | Why |
|---|---|---|
| PowerShell | `ms-vscode.powershell` | `dist.ps1` and `check-hardening-drift.ps1` are real code with `Set-StrictMode`. You want the script analyzer on them. |
| C/C++ | `ms-vscode.cpptools` | Provides the `cppvsdbg` debug type, which reads MSVC PDBs properly for the launcher binaries. |
| Hex Editor | `ms-vscode.hexeditor` | Inspecting `.ico` payloads, PE bytes, and downloaded archives during verification work. |
| WSL | `ms-vscode-remote.remote-wsl` | Opens window B. |

WSL profile only:

| Extension | ID | Why |
|---|---|---|
| CodeLLDB | `vadimcn.vscode-lldb` | Debugging the daemon and the GTK4 app on Linux. |
| ShellCheck | `timonwong.shellcheck` | `scripts/check.sh`, `clean.sh`, `blade-smoke-test.sh` are all `set -u` bash. |
| Hex Editor | `ms-vscode.hexeditor` | Reading captured HID feature reports byte by byte during Phase 3. This is the single most useful non-obvious extension for that repo. |

Two more that are worth it but that I have not re-verified as currently maintained **[verify before installing]**: a systemd unit-file syntax extension (search "systemd" in the marketplace) for `systemd/*.service|socket`, and an RPM spec-file extension for `packaging/razer-control-secureblue.spec`. Both files are small enough that plain text editing is survivable if the extensions look stale.

Deliberately not recommended: any extension that adds a second AI completion engine. You have two agents already; a third inline completer edits the same files without appearing in either agent's transcript, so when something breaks you cannot tell which tool did it.

### 3.3 User settings

Nothing scripts this part: paste it yourself, once per profile. Without it the editor runs `cargo check` rather than clippy, so it stays quiet about the exact warnings your gate will fail on. Paste into the **Rust · Windows** profile's user `settings.json`:

```jsonc
{
  // rust-analyzer: make the editor agree with your CI gate.
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.check.extraArgs": ["--workspace", "--all-targets", "--", "-Dwarnings"],
  // Keep rust-analyzer out of the target dir your builds and dist.ps1 use.
  "rust-analyzer.cargo.targetDir": true,
  "rust-analyzer.cargo.buildScripts.enable": true,
  "rust-analyzer.imports.granularity.group": "module",
  "rust-analyzer.inlayHints.parameterHints.enable": false,

  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer",
    "editor.formatOnSave": true,
    "editor.rulers": [100]           // matches rustfmt.toml max_width = 100
  },

  "files.eol": "\n",                  // .gitattributes says * text=auto eol=lf
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "editor.formatOnSave": true,
  "git.autofetch": true,

  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "powershell.codeFormatting.preset": "OTBS",

  "search.exclude": { "**/target": true },
  "files.watcherExclude": { "**/target/**": true }
}
```

For the **Rust · WSL** profile, the same block with these differences:

```jsonc
{
  "rust-analyzer.check.command": "clippy",
  // razer's check.sh uses --all-features, which compiles the hidraw backend.
  "rust-analyzer.check.extraArgs": ["--workspace", "--all-targets", "--all-features", "--", "-Dwarnings"],
  "rust-analyzer.cargo.allFeatures": true,
  "rust-analyzer.cargo.targetDir": true,
  "terminal.integrated.defaultProfile.linux": "bash",
  "[rust]": { "editor.rulers": [100] }
}
```

One caveat on `rust-analyzer.cargo.allFeatures`: it turns on `hidraw-backend` for analysis only. It changes nothing at runtime, because the daemon still requires `--backend hidraw`. It does mean rust-analyzer will type-check `backend_hidraw.rs`, which is what you want when editing it.

### 3.4 Per-repo `.vscode/`

**Nomad Launcher** ignores `.vscode/` in `.gitignore` today. My recommendation is to track `extensions.json` and `settings.json` (both are project facts, not preferences) and leave `launch.json` untracked (which launcher you debug and from where is personal). The gate itself belongs in `check.ps1`, not in a task file; see 7.1. `C:\src\Nomad-Launcher\.vscode\tasks.json`:

```jsonc
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "gate: check.ps1",
      "type": "shell",
      "command": "pwsh.exe -NoProfile -File .\\check.ps1",
      "problemMatcher": ["$rustc"],
      "group": { "kind": "test", "isDefault": true }
    },
    {
      "label": "dist: build unsigned",
      "type": "shell",
      "command": "pwsh.exe -NoProfile -File .\\dist.ps1",
      "problemMatcher": ["$rustc"]
    },
    {
      "label": "ui preview (ungoogled-chromium)",
      "type": "shell",
      "command": "cargo run -p nomad-ungoogled-chromium --example ui_preview",
      "problemMatcher": ["$rustc"]
    }
  ]
}
```

One task, because the gate lives in a committed script rather than in an editor file. Anything that can only be run from inside VS Code is invisible to CI, to both agents, and to you on a day you are in a plain terminal.

`.vscode/launch.json` for Nomad:

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Nomad-Firefox (MSVC)",
      "type": "cppvsdbg",
      "request": "launch",
      "program": "${workspaceFolder}/target/debug/Nomad-Firefox.exe",
      "cwd": "${workspaceFolder}/target/debug",
      "environment": [{ "name": "RUST_LOG", "value": "debug" }],
      "preLaunchTask": "cargo build firefox"
    }
  ]
}
```

That config references a build task, so add it to the `tasks` array above:

```jsonc
    {
      "label": "cargo build firefox",
      "type": "shell",
      "command": "cargo build -p nomad-firefox",
      "problemMatcher": ["$rustc"]
    }
```

Run the debugged launcher from a scratch directory, not the repo root, since it creates a `Nomad/` folder next to itself.

`C:\src\Nomad-Launcher\.vscode\settings.json`, the workspace half of 3.3:

```jsonc
{
  // dist.ps1 reads target/release directly; keep rust-analyzer out of that directory.
  "rust-analyzer.cargo.targetDir": true,
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.check.extraArgs": ["--workspace", "--all-targets", "--", "-Dwarnings"],
  "files.eol": "\n"
}
```

`C:\src\Nomad-Launcher\.vscode\extensions.json`:

```json
{
  "recommendations": [
    "rust-lang.rust-analyzer",
    "ms-vscode.powershell",
    "ms-vscode.cpptools",
    "ms-vscode.hexeditor",
    "tamasfe.even-better-toml",
    "fill-labs.dependi",
    "usernamehw.errorlens",
    "github.vscode-github-actions",
    "github.vscode-pull-request-github",
    "redhat.vscode-yaml",
    "eamodio.gitlens"
  ]
}
```

**razer-control-secureblue** can commit these, matching how it already commits `CLAUDE.md`. `.vscode/tasks.json`:

```jsonc
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "gate: scripts/check.sh",
      "type": "shell",
      "command": "./scripts/check.sh",
      "problemMatcher": ["$rustc"],
      "group": { "kind": "test", "isDefault": true }
    },
    {
      "label": "test: hidraw feature",
      "type": "shell",
      "command": "cargo test --locked -p razer-control-secureblue --features hidraw-backend",
      "problemMatcher": ["$rustc"]
    },
    {
      "label": "run: desktop UI (mock, WSLg)",
      "type": "shell",
      "command": "GDK_BACKEND=x11 RAZER_CONTROL_MOCK=1 cargo run -p razer-control-desktop",
      "isBackground": true,
      "problemMatcher": ["$rustc"]
    },
    {
      "label": "run: desktop UI with GTK inspector",
      "type": "shell",
      "command": "GDK_BACKEND=x11 RAZER_CONTROL_MOCK=1 GTK_DEBUG=interactive cargo run -p razer-control-desktop",
      "isBackground": true,
      "problemMatcher": ["$rustc"]
    },
    {
      "label": "validate: experimental gate still holds",
      "type": "shell",
      "command": "! cargo run -q -- validate profile gaming && cargo run -q -- validate profile gaming --experimental",
      "problemMatcher": []
    }
  ]
}
```

The last task is the local mirror of the assertion your RPM job makes in CI. It is two seconds and it is the single check that proves the safety gate has not been inverted.

`GTK_DEBUG=interactive` opens the GTK Inspector, which is how you inspect widget hierarchy and live-edit `desktop/resources/style.css` values without a rebuild. Given the Synapse-theme work in your recent commits, that will save more time than any extension on the list.

`.vscode/launch.json` for razer:

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug daemon (dry-run)",
      "type": "lldb",
      "request": "launch",
      "cargo": { "args": ["build", "--bin=razer-control"], "filter": { "kind": "bin" } },
      "args": ["daemon"],
      "env": { "RUST_LOG": "debug" },
      "cwd": "${workspaceFolder}"
    },
    {
      "name": "Debug desktop (mock)",
      "type": "lldb",
      "request": "launch",
      "cargo": { "args": ["build", "-p", "razer-control-desktop"], "filter": { "kind": "bin" } },
      "env": { "RAZER_CONTROL_MOCK": "1", "GDK_BACKEND": "x11" },
      "cwd": "${workspaceFolder}"
    }
  ]
}
```

`.vscode/settings.json` for razer, the workspace half of 3.3:

```jsonc
{
  // check.sh uses --all-features, so the editor should too.
  "rust-analyzer.cargo.allFeatures": true,
  "rust-analyzer.cargo.targetDir": true,
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.check.extraArgs": ["--workspace", "--all-targets", "--all-features", "--", "-Dwarnings"]
}
```

`.vscode/extensions.json` (razer):

```json
{
  "recommendations": [
    "rust-lang.rust-analyzer",
    "vadimcn.vscode-lldb",
    "tamasfe.even-better-toml",
    "fill-labs.dependi",
    "usernamehw.errorlens",
    "timonwong.shellcheck",
    "ms-vscode.hexeditor",
    "github.vscode-github-actions",
    "redhat.vscode-yaml",
    "eamodio.gitlens"
  ]
}
```

---

## 4. Toolchain and cargo tooling

### 4.1 Declare the toolchain policy in both repos

Add `rust-toolchain.toml` at each repo root after reviewing the current compatibility
policy. A `stable` channel declaration keeps required components and targets consistent,
but it follows new stable releases and is not an immutable version pin. Exact MSRV
verification belongs in a separate CI job when the project promises one.

Nomad (`C:\src\Nomad-Launcher\rust-toolchain.toml`):

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
targets = ["x86_64-pc-windows-msvc"]
```

razer (`~/src/razer-control-secureblue/rust-toolchain.toml`):

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
```

If you want MSRV to mean something in Nomad, pin `channel = "1.77.0"` in a separate CI job rather than in the file, so daily work still gets current clippy. And add `rust-version` to razer's `Cargo.toml`: edition 2024 requires Rust 1.85 or newer, so declaring it stops a Fedora-packaged older rustc from failing confusingly.

### 4.2 Cargo tools worth having on both sides

Install `cargo-binstall` first. It fetches prebuilt binaries instead of compiling each tool from source, which turns roughly twenty minutes into roughly one. The bootstrap scripts already do this.

```bash
cargo install cargo-binstall --locked
cargo binstall -y cargo-nextest cargo-audit cargo-machete cargo-deny bacon typos-cli
```

If `binstall` is unavailable for a tool, fall back to a source build:

```bash
cargo install cargo-nextest --locked   # faster, better test output; agents parse it well
cargo install cargo-audit --locked     # both repos' CI uses it
cargo install cargo-machete --locked   # razer's check.sh already looks for it
cargo install cargo-deny --locked      # license + advisory + source policy; see below
cargo install bacon --locked           # background cargo check/clippy; the loop you want while an agent edits
cargo install typos-cli --locked       # doc-heavy repos
```

`cargo-deny` deserves a specific note for razer. The repo is GPL-2.0-only because `src/protocol.rs` derives from GPL upstreams, and `CLAUDE.md` tells agents to keep new files GPL-2.0-only. A `deny.toml` with a `[licenses]` allow-list turns that convention into a check that fails when someone pulls in an incompatible dependency. That is exactly the kind of rule an agent will otherwise violate politely and confidently.

Generate a starting file with `cargo deny init`, then reduce it to something like this. Current cargo-deny denies every licence that is not explicitly allowed, so the allow-list is the whole policy; the older `copyleft`, `unlicensed`, `deny`, and `allow-osi-fsf-free` keys were removed and now raise errors if you copy them from an old example.

`~/src/razer-control-secureblue/deny.toml`:

```toml
[licenses]
# Everything not listed here is denied. GPL-2.0-only is the project licence;
# the rest are the permissive licences its dependency tree actually uses.
allow = [
    "GPL-2.0-only",
    "MIT",
    "Apache-2.0",
    "Apache-2.0 WITH LLVM-exception",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-3.0",
    "Zlib",
]
confidence-threshold = 0.9

[bans]
multiple-versions = "warn"

[advisories]
yanked = "deny"

[sources]
unknown-registry = "deny"
unknown-git = "deny"
```

Run `cargo deny check` once and add whatever legitimate licence it flags rather than guessing the list up front. A licence you do not recognise appearing in that output is itself the useful signal.

For Nomad the same file works with `"MIT"` and `"Apache-2.0"` in place of the GPL entry, since it is dual-licensed MIT OR Apache-2.0.

`bacon` is the piece that changes how the agent loop feels: leave `bacon clippy-all` running in a split terminal while an agent edits, and you see breakage the moment it lands rather than at the end of a turn.

---

## 5. The agent layer

### 5.1 Division of labour: one agent owns a task end to end

Both agents are full implementers here. You pick one per task and it carries that task from planning through to a passing gate. Neither is capped.

That works because the thing you are actually avoiding is not "Codex has write access", it is **two agents editing the same working tree at the same time**. Concurrent edits produce overwrites that neither transcript reports: one agent writes a function, the other rewrites the same file from a copy it read a minute ago, and the first change is gone silently. Serial ownership removes that risk entirely, which means the read-only constraint has nothing left to buy.

What this costs, and it is worth naming: the guardrails in 5.6 are Claude Code mechanisms. Hooks, `permissions.deny`, and `.claude/rules/` do not exist for Codex, and I could not verify any hook equivalent in its documentation. So a rule you enforce for one agent is only guidance for the other. Section 5.7 covers what to do about that.

An adversarial second opinion is still worth having on changes that touch an invariant, but it is now an **optional pass you invoke**, not a standing role. Either agent can review the other's diff; see 5.9.

### 5.2 Instruction files: one source of truth, two readers

`AGENTS.md` is the canonical cross-agent project policy. Codex reads it directly.
Claude Code reads `CLAUDE.md`, so `CLAUDE.md` imports `AGENTS.md` at session start and
may append Claude-only operational material below. Never put a critical project
invariant only in `CLAUDE.md`, `.claude/rules/`, a hook, or an untracked personal note.

**razer-control-secureblue** (committed, since it already commits `CLAUDE.md`): move the existing content to `AGENTS.md`, then make `CLAUDE.md` this:

```markdown
@AGENTS.md

## Claude Code specifics

- Use plan mode for any change to `src/lib.rs` (capability table), `src/protocol.rs`
  (golden bytes), or `src/backend_hidraw.rs`. Present the plan before editing.
- The `run-desktop-ui` skill is the only supported way to launch the GUI here.
- Cross-session memory lives in the private `razer-control-memory` repo; read its
  README before assuming an environment fact.
```

Do not use a symlink for this on Windows. Symlink creation needs Administrator or Developer Mode there, and this repo is checked out on both sides. The `@AGENTS.md` import works everywhere.

**Nomad Launcher** gitignores `CLAUDE.md`, so it has no committed agent instructions at all today. That is a real gap, and it is worth separating two things that look like one decision.

The valuable artifact is not the instruction file. It is the **list of invariants**: the seven statements about what must remain true, which are what stop an agent from loosening a signature check to make a test pass. Untracked, that list exists on exactly one machine, and a fresh clone or a dead disk loses it. That is a bad asymmetry for the repo where a wrong agent decision has the worst consequences.

There is a fair reason you might not want an `AGENTS.md` at the root of a privacy tool: it advertises that AI touched the code, and some of your users will read that as a reason to trust it less. The fix for that is framing, not secrecy. Those invariants are engineering documentation, not agent instructions. So:

1. **Put the invariants in `SPEC.md`** as a new section, or in a `CONTRIBUTING.md`. They sit naturally next to `SECURITY.md` in a project that already publishes its threat model. For a security tool, "here is what must remain true, and here is what went wrong the time it wasn't" reads as rigour rather than as scaffolding.
2. **Commit a short `AGENTS.md`** that points there rather than restating it.
3. **Keep `CLAUDE.md` untracked**, as a one-line `@AGENTS.md` import plus whatever personal notes you want.

Nothing is duplicated, nothing is lost on a reclone, and the public artifact is documentation because that is what it is.

The thin `AGENTS.md`:

```markdown
# AGENTS.md

Guidance for AI coding agents working in this repository. Humans want SPEC.md.

Before changing anything under `core/src/` that touches downloading, verifying,
extracting, or installing a browser, read the **Invariants** section of SPEC.md
in full. It is short, and every item in it is load-bearing. A change that
weakens one of those statements is a defect even when it fixes the bug in front
of you.

Build and test commands are in the Commands section of SPEC.md. Match CI locally
with `pwsh -File .\check.ps1` before assuming a change is green.
```

This is written as an explicit instruction to read the project specification. Codex
loads `AGENTS.md` directly, while Claude reaches it through the documented
`@AGENTS.md` adapter.

The content to move into `SPEC.md`, derived from what is actually in the tree:

```markdown
## Invariants

These statements must remain true of Nomad. A change that weakens one is a defect
regardless of what it fixes, and reviewers (human or otherwise) should treat it
that way.

1. **Every download is verified before it is executed.** GPG where upstream
   publishes a usable key, SHA-256/512 otherwise, Authenticode signer pinning for
   Bitwarden. A change that adds a download path without verification, or that
   makes a verification failure non-fatal, breaks this.
2. **Embedded upstream keys are evidence, not configuration.** `core/keys/*.asc`
   and `nomad-release-signing-key.asc` are never edited to make a test pass. A key
   rotation upstream is a deliberate, separately reviewed commit.
3. **Build hardening stays on.** `.cargo/config.toml` sets `control-flow-guard=yes`
   and `/DEPENDENTLOADFLAG:0x800`. Neither is removed to work around a build issue.
4. **The scrub never deletes a real installation.** `lib.rs` checks each runtime
   directory for an existing install and leaves the whole directory alone if it
   finds one. Versions before v1.0.6 got this wrong and deleted browsers people
   had installed themselves; leaving an unscrubbed trace is the better failure.
5. **No installer behaviour.** No HKLM writes, no services, nothing in `%APPDATA%`
   during normal operation.
6. **RUSTSEC ignores are documented, never silent.** Every `--ignore` in ci.yml
   carries a written justification for why the advisory cannot reach a shipped
   binary. An ignore without one is not acceptable.
7. **Release builds do not restore a cargo cache.** Deliberate: a poisoned cache
   entry could end up inside a signed binary. Not an oversight to optimise away.

## Conventions

- `rustfmt.toml` sets `max_width = 100`. Comments explain *why*, in prose, matching
  the existing style in `.cargo/config.toml` and `ci.yml`.
- Workflow actions are pinned to commit SHAs and jobs start from `permissions: {}`.
  Keep both when editing workflows; `zizmor` gates this in CI.
- A behaviour change that contradicts this document updates it in the same commit.
- New browser support means: a `core/src/browsers/<name>.rs`, a `launchers/<name>/`
  crate, a verification story in §2, and a row in the README table.

## Commands

    pwsh -File .\check.ps1       # the full local gate: fmt, clippy, test, audit
    pwsh -File .\dist.ps1        # release build + SHA256SUMS (signing needs NOMAD_SIGN_CERT)

`check.ps1` mirrors CI. Match it locally before assuming a change is green.
```

That list is worth writing carefully once. It is the thing that stops an agent from "fixing" a failing signature test by loosening the signature check, which is the single most likely way an agent damages this project. It also happens to be good documentation for a human reading the repo for the first time, which is the point of putting it in `SPEC.md` rather than in a file addressed to robots.

### 5.3 Claude Code configuration

**User settings** (`~/.claude/settings.json` on Linux/WSL, `C:\Users\<you>\.claude\settings.json` on Windows). The bootstrap scripts write this file when it does not already exist; if yours does, merge the block by hand. The schema line gives you autocomplete and inline validation in VS Code:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(cargo fmt *)",
      "Bash(cargo tree *)",
      "Bash(cargo metadata *)",
      "Bash(rustup show *)"
    ],
    "deny": [
      "Read(**/.env)",
      "Read(**/*.pfx)",
      "Read(**/*.p12)",
      "Read(~/.gnupg/**)",
      "Read(~/.ssh/**)"
    ]
  },
  "autoMemoryEnabled": true,
  "includeCoAuthoredBy": false
}
```

Global permissions deliberately include only low-risk, project-agnostic inspection or
formatting commands. Put build, test, lint, audit, package, and project-script
permissions in the repository's `.claude/settings.json` after reviewing that
repository's gate and side effects. Bash patterns are prefix/glob matches, and a
`Read` deny rule also blocks Edit and Write on the same path, which is what you want
for key material.

**VS Code extension settings** (Settings > Extensions > Claude Code):

| Setting | Value | Reason |
|---|---|---|
| `claudeCode.initialPermissionMode` | `plan` | For repos where a wrong edit is a security regression, starting in plan mode is worth the extra keystroke. Note the extension reads this from **user** settings and ignores workspace values. |
| `claudeCode.preferredLocation` | `sidebar` | Keeps the diff view usable. |
| `claudeCode.autosave` | `true` (default) | Avoids Claude reading a stale buffer. |
| `claudeCode.respectGitIgnore` | `true` (default) | Keeps `target/` out of searches. |
| `claudeCode.allowDangerouslySkipPermissions` | `false` | Leave it off. Neither repo is a throwaway sandbox. |

Useful things in the panel that are easy to miss: plan mode opens the plan as a full Markdown document you can comment on inline before approving; checkpoints let you rewind code, fork the conversation, or both, from the hover menu on any message; `/usage` shows what is eating your plan limits, broken down per skill, subagent, plugin, and MCP server, which is how you find out an MCP server you forgot about is costing you 15% of every session.

**Project rules.** For razer, `.claude/rules/` is a better home than a growing `CLAUDE.md`, because rules can be path-scoped and only load when Claude touches matching files. Suggested split (note that razer's `.gitignore` currently excludes all of `.claude/` except the one skill, so add `!/.claude/rules/` if you want these committed):

`.claude/rules/protocol.md`:

```markdown
---
paths:
  - "src/protocol.rs"
  - "src/backend_hidraw.rs"
---

# Wire protocol rules

- Every packet the encoder can emit is pinned by model-specific golden-byte tests.
  If a golden-byte test fails after your change, the default assumption is that
  your change is wrong. Updating golden bytes is a deliberate act that requires an
  explanation of what upstream evidence justifies the new encoding.
- `REPORT_LEN`, offsets, and CRC live here and nowhere else.
- Response CRC window: until Phase 3 records `crc_window=` on real hardware, the
  validator accepts both the lineage window and OpenRazer's. Do not narrow it.
```

`.claude/rules/capabilities.md`:

```markdown
---
paths:
  - "src/lib.rs"
  - "docs/DEVICES.md"
---

# Capability table rules

- Any edit to `DeviceCapabilities` must land in the same commit as an evidence
  entry in docs/DEVICES.md.
- Values labelled "Declared" (from Synapse or upstream, not confirmed on hardware)
  must never be presented as verified, in code comments, docs, or UI strings.
- `validate_operation()` is the single chokepoint. Do not add a second path that
  reaches a Backend without passing through it.
```

### 5.4 Codex configuration

Codex reads `~/.codex/config.toml` (user), `.codex/config.toml` (project, trusted projects only), and profiles at `~/.codex/<name>.config.toml`. Precedence runs CLI flags, then project config, then profile, then user, then system.

`~/.codex/config.toml`. The bootstrap scripts write this file if it does not exist and
append the GitHub block after GitHub CLI authentication succeeds. They never read the
token. Existing settings are preserved except for appending a missing GitHub table;
merge other settings by hand.

```toml
# Codex owns whole tasks, same as Claude Code. The brake is the approval
# policy, not a read-only sandbox.
model = "gpt-5.6"                 # use whatever your plan exposes; this is the docs' example
model_reasoning_effort = "high"
approval_policy = "on-request"    # untrusted | on-request | never
sandbox_mode = "workspace-write"  # read-only | workspace-write | danger-full-access
personality = "pragmatic"
web_search = "cached"             # switch a single run to live search with --search

[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_MCP_PAT"
startup_timeout_sec = 20

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
# Optional: a free key raises rate limits.
# bearer_token_env_var = "CONTEXT7_API_KEY"
```

On the Windows side, add the platform block:

```toml
[windows]
sandbox = "elevated"    # OpenAI's recommended native Windows mode
```

A second profile for a deliberate review pass, where you want Codex reading and reasoning but definitely not editing:

`~/.codex/review.config.toml`:

```toml
model_reasoning_effort = "high"
approval_policy = "on-request"
sandbox_mode = "read-only"
```

Invoke the read-only profile with `codex --profile review`. OpenAI's configuration
documentation defines `--profile <name>` and the corresponding
`~/.codex/<name>.config.toml` file.

`approval_policy = "on-request"` is the setting that matters here. It keeps commands asking before they run, which is the same posture Claude Code's Manual and Plan modes give you. Do not set it to `never` on these two repos: a command that reaches the Blade EC, or that rewrites a signing key, is exactly the class of thing you want to see before it happens.

### 5.5 Skills: write once, serve both agents

Skills are the highest-leverage piece of this whole setup, and you have already discovered why: `run-desktop-ui` encodes twenty minutes of WSLg archaeology (the XWayland fallback, the 1x1 helper-window trap, the fact that pill coordinates go stale between activations) that no model will re-derive correctly. That skill is worth more than any MCP server on the list.

The two agents look in different places:

| Agent | Repo scope | User scope |
|---|---|---|
| Claude Code | `.claude/skills/<name>/SKILL.md` | `~/.claude/skills/` |
| Codex | `.agents/skills/<name>/SKILL.md` | `~/.agents/skills/` |

Codex documents support for symlinked skill folders, so keep the canonical copy where it already lives and link it:

```bash
cd ~/src/razer-control-secureblue
mkdir -p .agents/skills
ln -s ../../.claude/skills/run-desktop-ui .agents/skills/run-desktop-ui
printf '/.agents/skills/*\n!/.agents/skills/run-desktop-ui\n' >> .gitignore
```

One caveat: a committed symlink resolves on Linux but may land as a plain text file in the Windows checkout, depending on `core.symlinks` and Developer Mode. If that bites you, either leave `.agents/skills/` untracked (each machine creates its own link) or copy the file instead of linking and add a check to `scripts/check.sh` that the two copies match.

Both agents use the same `SKILL.md` frontmatter (`name`, `description`), so one file genuinely serves both. Codex invokes explicitly with `$skill-name` in the CLI or `@skill-name` in ChatGPT, and implicitly by matching the description; Claude Code invokes by relevance or by name. Write the `description` as trigger conditions, not as a summary. Codex caps the skill list it shows the model at about 2% of the context window or 8,000 characters, so a vague description loses to a specific one.

Skills worth writing next, in order of payoff:

1. **`nomad-verify-release`** (Nomad). The `dist.ps1` plus offline-GPG plus draft-release dance is exactly the kind of multi-step procedure that lives in your head. Encode: what `NOMAD_SIGN_CERT` accepts, where `signtool.exe` hides, why signing runs before SHA256SUMS, and that the `.asc` is produced offline and attached last.
2. **`razer-phase3`** (razer). `docs/PHASE3-PERF-VERIFICATION.md` is already the procedure; a skill wrapper makes an agent follow it in order and stop at the first surprise instead of improvising, which is the documented requirement.
3. **`add-browser-launcher`** (Nomad). Nine near-identical launcher crates means the tenth is a mechanical task with a checklist: core module, launcher crate, icon, SPEC.md row, README row, verification story. High value, low risk.
4. **`golden-bytes-change`** (razer). A skill that refuses to update golden bytes without citing an upstream source and adding a DEVICES.md entry.

### 5.6 Hooks: turn conventions into enforcement

`CLAUDE.md` is context, not enforcement; the docs are explicit that Claude treats it as guidance and that a hard block belongs in a `PreToolUse` hook. For two repos whose entire value proposition is a safety property, that distinction matters.

**razer: block accidental hardware writes.** Add to `~/src/razer-control-secureblue/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-hardware.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/fmt-rust.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

`.claude/hooks/guard-hardware.sh` (make it executable):

```bash
#!/usr/bin/env bash
# Blocks any command that could reach the EC. Hardware writes are a human decision.
set -u
CMD=$(jq -r '.tool_input.command // ""')

case "$CMD" in
  *"--backend hidraw"*|*" probe"*|*"--experimental"*)
    jq -n --arg c "$CMD" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ("Blocked: this command can reach the Blade EC (\($c)). Hardware writes and probe runs are performed by the maintainer following docs/PHASE3-PERF-VERIFICATION.md, never by an agent.")
      }
    }'
    exit 0
    ;;
esac
exit 0
```

`.claude/hooks/fmt-rust.sh`:

```bash
#!/usr/bin/env bash
set -u
FILE=$(jq -r '.tool_input.file_path // ""')
case "$FILE" in
  *.rs) rustfmt --edition 2024 "$FILE" >/dev/null 2>&1 ;;
esac
exit 0
```

Three things that will bite you if you skip them:

```bash
chmod +x .claude/hooks/guard-hardware.sh .claude/hooks/fmt-rust.sh
sudo dnf install -y jq            # both scripts parse the hook payload with jq
```

And razer's `.gitignore` currently excludes all of `.claude/` except the one shared skill, so these files stay untracked unless you un-ignore them. If you want them committed, add:

```gitignore
!/.claude/settings.json
!/.claude/hooks/
!/.claude/rules/
```

A hook that is not executable, or a missing `jq`, fails silently: the tool call proceeds as if no hook existed. That is why section 9 has you test the block rather than assume it. Exit code 2 also blocks, with stderr shown to you; the JSON form above is clearer because it explains itself in the transcript.

**Nomad: protect key material and hardening flags.** Windows has no `jq` by default, so use PowerShell. `.claude/settings.json` in the Nomad checkout (untracked, since `.claude/` is gitignored there):

```json
{
  "permissions": {
    "deny": [
      "Edit(/nomad-release-signing-key.asc)",
      "Edit(/core/keys/**)",
      "Edit(/.cargo/config.toml)"
    ],
    "ask": [
      "Edit(/.github/workflows/**)",
      "Edit(/core/src/gpg.rs)",
      "Edit(/core/src/authenticode.rs)",
      "Bash(git push *)"
    ]
  }
}
```

Path rules in project settings anchor at the project root when they start with `/`, which is what those rules rely on. The deny list is not paranoia: an agent that cannot make a signature test pass will eventually consider editing the embedded key, and this makes that impossible rather than merely discouraged.

If you want the same fmt-on-edit behaviour on Windows, `.claude/hooks/fmt-rust.ps1`:

```powershell
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$file = $payload.tool_input.file_path
if ($file -and $file.EndsWith('.rs')) { rustfmt --edition 2021 $file 2>$null }
exit 0
```

wired up with `"command": "pwsh -NoProfile -File ${CLAUDE_PROJECT_DIR}/.claude/hooks/fmt-rust.ps1"`.

### 5.7 The same protection, on the Codex side

Everything in 5.6 is a Claude Code mechanism. When Codex owns a task instead, none of it applies: no hooks, no `permissions.deny`, no path rules. I could not find a hook equivalent in the Codex documentation, so treat that asymmetry as real rather than assuming parity **[verify: re-check if Codex adds hooks]**.

Three levers close most of the gap.

**1. Keep `approval_policy = "on-request"`.** This is the main one. Codex asks before running commands, so a `--backend hidraw` invocation or a `git push` surfaces as a prompt rather than a fait accompli. It is coarser than a targeted deny rule, since it asks about everything rather than about the dangerous things, but it catches the same events.

**2. Put the prohibitions in `AGENTS.md`, in imperative form.** Codex reads that file; it does not read `.claude/rules/`. So anything encoded as a Claude rule needs a plain-language twin in `AGENTS.md`. For razer, the two that matter:

```markdown
## Never do these

- Never run `razer-control` with `--backend hidraw`, `--experimental`, or the
  `probe` subcommand. Those reach the laptop EC. Hardware runs are performed by
  the maintainer following docs/PHASE3-PERF-VERIFICATION.md.
- Never edit golden-byte expectations in `src/protocol.rs` to make a test pass.
  A failing golden-byte test means the change is wrong, not the test.
```

For Nomad, the equivalent covers the embedded keys, `.cargo/config.toml`, and the RUSTSEC ignore list. This is guidance rather than enforcement, which is exactly why it needs to be blunt and specific.

**3. Best of all: remove the capability instead of forbidding it.** The strongest protection is tool-independent. razer's hardware path only exists in a binary built with `--features hidraw-backend`, so if your normal dev loop never passes that flag, no agent of any kind can reach the EC, because the code is not in the binary. Build with the feature only when you are deliberately doing hardware work. A guard that lives in the build is one you cannot forget to install for the other tool.

### 5.8 MCP servers: keep the surface small

Every connected MCP server spends context on tool definitions in every session, and Claude Code's `/usage` now attributes plan consumption per server precisely because this adds up. For two Rust repos, most of the MCP ecosystem is noise. Two are worth it.

**GitHub** (both repos): issues, PRs, release assets, and Actions logs without leaving the session. Nomad's launchers already talk to the GitHub releases API for upstream discovery, so an agent that can read a real release payload debugs those code paths much faster.

Use ordinary `git` and `gh` commands unless MCP adds a capability you actually need.
Install `gh`, then authenticate separately on each build side:

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth status --hostname github.com --active
```

Run the relevant bootstrap again. It checks authentication without reading the token
and adds Codex's `bearer_token_env_var` configuration when needed. Launch Codex through
the matching helper in `helpers/`; the helper reads the GitHub CLI token and sets
`GITHUB_MCP_PAT` for Codex and its descendants. The PowerShell helper temporarily
sets the calling process environment and restores the prior value in `finally`.
Do not place that variable in `~/.bashrc` or a persistent Windows user environment.

Claude Code's documented GitHub MCP method uses a fine-grained PAT in an authorization
header. This is not process-only: `claude mcp add --scope user` stores the resulting
server configuration and header in Claude's user scope. The bootstraps therefore do
not run it automatically. If you accept that local persistence and need GitHub MCP,
create a token limited to the required repositories and add it manually:

```bash
# Claude Code, user scope so both repos get it
claude mcp add --transport http --scope user github https://api.githubcopilot.com/mcp/ \
  --header "Authorization: Bearer <fine-grained-token>"
claude mcp list        # expect: ✔ Connected
```

Remove or replace the Claude server configuration when the token is rotated. Codex
reads `bearer_token_env_var` at connect time, and the helper supplies it from GitHub
CLI's credential store without placing it in the persistent Codex config.

**Context7** (mainly razer): current API docs for fast-moving crates. `gtk4-rs` 0.9, `libadwaita` 0.7 with `v1_4`, `eframe`/`egui` 0.31 and `ksni` 0.2 are all libraries where a model's training-time API memory is a liability, and both repos pin specific minor versions.

```bash
claude mcp add --transport http --scope user context7 https://mcp.context7.com/mcp
```

A free key from context7.com/dashboard raises rate limits; pass it as `--header "Authorization: Bearer <key>"` if you get one.

For project-scoped servers you want committed and shared, put them in `.mcp.json` at the repo root. The shape is the same `mcpServers` object other MCP clients use:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    }
  }
}
```

The `"type": "http"` line is not optional. Claude Code reads an entry with no `type` as a stdio server, skips it, and reports `MCP server "<name>" has a "url" but no "type"`. Project-scoped servers also need approving once: run `claude` in the folder, accept the workspace trust dialog, and approve the server. Until then `claude mcp list` shows it as pending rather than connected.

For these two repos, user scope is simpler and there are no collaborators to share with, so `.mcp.json` is more useful as a pattern for future projects than as something you need today.

What I would *not* add: filesystem MCP (both agents already have file tools), a browser MCP for these repos (neither is a web project; the GTK UI is driven by the `run-desktop-ui` skill and the Nomad UI by its `ui_preview` example), or any "memory" MCP. On memory specifically, Claude Code's built-in auto memory writes to `~/.claude/projects/<project>/memory/` and loads `MEMORY.md` at session start, and you have already built the durable half yourself with the private `razer-control-memory` repo. That combination is better than a memory server because it is inspectable and versioned.

### 5.9 The optional second-opinion pass

Not a standing role, and not one-directional: whichever agent did not write the change can review it. Worth invoking when a diff touches an invariant, skippable for a typo fix.

The value is that the reviewer is not carrying the author's context. It did not spend an hour convincing itself the approach was right, so it reads the diff for what it says rather than for what it was meant to say. Run it with a read-only profile (5.4) so a review stays a review.

1. **Frame the task in plan mode.** In the VS Code panel, plan mode opens the plan as a Markdown document; comment inline on the parts you disagree with before approving. For anything touching `validate_operation`, `protocol.rs`, `gpg.rs`, or `install.rs`, do not skip this.
2. **Implement on a branch.** `git switch -c fix/whatever`. Both repos are PR-merge shaped; keep that.
3. **Run the local gate yourself, not just the agent.** `./scripts/check.sh` for razer, the `gate:` task for Nomad. Agents are good at declaring victory.
4. **Hand the other agent the diff with a specific brief.** Not "review this". Something like:

   ```
   codex exec --search "Review the working-tree diff against main in this repo.
   The project's claimed invariant is that no HID write reaches hardware unless
   the device is recognised, the value passes the compiled capability table, and
   the operation was explicitly opted into. Find every way this diff could
   violate that, including through a path that does not obviously touch
   validate_operation. Report only concrete findings with file:line. If you find
   none, say so and name the two weakest points you considered."
   ```

   The "name the weakest points you considered" clause is the difference between a review and a rubber stamp. Ask for the reasoning trail, not the verdict.
5. **Feed findings back as claims, not orders.** "The reviewer says X at line N; verify and either fix or explain why it is wrong." Both models are agreeable; asking the author to adjudicate rather than comply is how you avoid churn from a false positive.
6. **Repeat the gate. Then commit.**

For Nomad, the equivalent brief is the verification chain: "every downloaded artifact is verified before execution, and a verification failure is fatal". For razer's GUI work, the brief is "clients hold zero policy; every action is one IPC line".

Two things that make this cheaper. Codex's IDE extension can review a diff and let you follow up in the same chat, which is lower friction than the CLI for small changes. And `/usage` in Claude Code tells you when a review habit is costing more than it returns.

### 5.10 Parallel work with worktrees

You work one agent per task, so this is not a daily need. It matters on the day you want two unrelated tasks moving at once: give each its own directory rather than sharing a tree.

```bash
git worktree add ../razer-wt-lighting feature/lighting-page
git worktree add ../razer-wt-copr chore/copr-packaging
```

Open each as its own VS Code window with its own agent session. Claude Code's auto memory is shared across worktrees of the same repository (it keys on the git repo), which is what you want: a fact learned in one worktree is available in the other. A gitignored `CLAUDE.local.md` is *not* shared across worktrees, so if you keep personal notes, import them from your home directory instead:

```markdown
# Individual Preferences
- @~/.claude/my-project-instructions.md
```

Set `CARGO_TARGET_DIR` per worktree or accept full rebuilds; for a GTK4 workspace that difference is minutes, not seconds.

---

## 6. `addyosmani/agent-skills`: worth it, with edits

Yes, I know it, and I re-read it at HEAD today rather than from memory. It is 24 skills under `skills/<name>/SKILL.md`, plus 8 slash commands mapping to a lifecycle (`/spec`, `/plan`, `/build`, `/test`, `/review`, `/webperf`, `/code-simplify`, `/ship`), 4 personas under `agents/` usable as Claude Code subagents, shared checklists under `references/`, a session-start hook, and an eval harness. It ships as a Claude Code plugin marketplace *and* a Codex plugin, sharing one `skills/` directory: `.claude-plugin/` for Claude, `.codex-plugin/plugin.json` plus `.agents/plugins/marketplace.json` for Codex.

Your repo history says you already vendored it and then removed it (`b1ee67b chore: remove vendored agent-skills directory`). That was the right call and the reason is worth stating: vendoring copies 24 skills into a repo that needs about four of them, and freezes them at a commit. Install it as a plugin instead, at user scope, so it applies across projects and updates on refresh.

```
# Claude Code
/plugin marketplace add addyosmani/agent-skills
/plugin install agent-skills@addy-agent-skills
```

```bash
# Codex (requires Codex CLI v0.122+ per their docs)
codex plugin marketplace add addyosmani/agent-skills
codex plugin add agent-skills@agent-skills
```

Install it for you (user scope), not for the project, since neither repo has collaborators who agreed to this workflow.

**What genuinely earns its place for your two repos:**

- `code-review-and-quality` and the `security-auditor` persona. The closest thing in the collection to what these repos actually need, and it works inside whichever agent is running rather than replacing the second-opinion pass in 5.9.
- `debugging-and-error-recovery`. Relevant to the Phase 3 procedure's "stop at the first surprise" discipline.
- `spec-driven-development` and `documentation-and-adrs`. You already work this way: `SPEC.md` is the source of truth for Nomad, `DEVICES.md` is an evidence log for razer. These skills reinforce an existing habit rather than imposing a new one.
- `git-workflow-and-versioning`. Both repos have careful release mechanics.
- `ci-cd-and-automation`. Nomad's workflows (pinned SHAs, `permissions: {}`, attestation, zizmor) are unusually strict and worth having a skill reason about before edits.

**What to ignore here:** `frontend-ui-engineering`, `browser-testing-with-devtools`, `performance-optimization` and `webperf` are web-oriented and will not help a GTK4 app or a Windows launcher. `interview-me` and `idea-refine` are for greenfield definition; both your projects have specs already.

**The real caveat, and it is not about quality.** A large skill catalogue costs context in every session and increases the chance an agent takes a procedural detour when you wanted a two-line fix. Codex caps the skill list at roughly 2% of context or 8,000 characters, and Claude Code's `/usage` will show you skill-level attribution. Install it, then watch `/usage` for a week. If the lifecycle commands are not changing outcomes on *these* repos, disable the skills you do not use. Codex supports per-skill disabling in `~/.codex/config.toml`:

```toml
[[skills.config]]
path = "/home/you/.agents/skills/frontend-ui-engineering/SKILL.md"
enabled = false
```

The deeper point: the collection's value to you is as a **model for writing your own skills**, more than as a set of skills to run. Read `docs/skill-anatomy.md` and `CONTRIBUTING.md`, then apply that structure (Overview, When to Use, Process, Common Rationalizations, Red Flags, Verification) to the four project-specific skills in 5.5. The "Common Rationalizations" section in particular is the pattern you want for `golden-bytes-change`: an explicit list of the excuses an agent will reach for when a golden-byte test fails, with the counter for each. Nothing generic will encode that for you.

---

## 7. Per-repo playbooks

### 7.1 Nomad Launcher

**Environment.** Windows-native only. MSVC toolchain (`rustup default stable-x86_64-pc-windows-msvc`), Windows SDK for `signtool.exe`, PowerShell 7 (`pwsh`) since `dist.ps1` uses `Set-StrictMode -Version Latest`. Do not attempt to build this in WSL; the `.cargo/config.toml` rustflags are `cfg(windows)`-scoped and the whole product is PE-shaped.

**Editor.** Nothing special beyond section 3, except: put `"rust-analyzer.cargo.targetDir": true` in the workspace settings too. `dist.ps1` reads `target/release/Nomad-*.exe` directly, and you do not want rust-analyzer holding a lock on that directory when you run a dist build.

**Testing.** The integration tests use `httpmock`, so they are real network-shaped tests. `cargo nextest run --workspace` gives better isolation and much better failure output than `cargo test` here. Keep `cargo test --workspace` as the CI-parity command.

**Gaps I would close, in priority order:**

1. **Add `check.ps1`, the missing gate.** razer has `scripts/check.sh`: one command, committed, that mirrors CI. Nomad has no equivalent, which is why its gate ended up scattered across a README, a workflow file, and an untracked editor task. A gate that only exists inside VS Code is invisible to CI, to both agents, and to you in a plain terminal. Commit this at the repo root:

   ```powershell
   #Requires -Version 7.0
   # One-command repo health check.  Mirrors .github/workflows/ci.yml: the same
   # formatting, lint, test, and advisory gates a pull request has to pass,
   # runnable locally before you push.  Runs every step even if an earlier one
   # fails, then exits non-zero if any failed, so you see the whole picture in
   # one pass.
   #
   #   pwsh -File .\check.ps1
   #
   # cargo-audit is optional and skipped with a note when absent:
   #   cargo install cargo-audit --locked

   Set-StrictMode -Version Latest
   $ErrorActionPreference = 'Stop'
   Set-Location $PSScriptRoot

   $global:LASTEXITCODE = 0
   $script:Failed = 0

   # Keep this list identical to the ignores in .github/workflows/ci.yml.  Each
   # one there carries a written justification for why the advisory cannot reach
   # a shipped binary; do not add an ignore here without adding it there too.
   $AuditIgnores = @(
       '--ignore', 'RUSTSEC-2023-0071',
       '--ignore', 'RUSTSEC-2026-0194',
       '--ignore', 'RUSTSEC-2026-0195'
   )

   function Step {
       param([string]$Label, [scriptblock]$Command)
       Write-Host ""
       Write-Host "== $Label ==" -ForegroundColor Cyan
       # One native command per Step; reset stale native status before cmdlets.
       $global:LASTEXITCODE = 0
       try {
           & $Command
           if ($LASTEXITCODE -ne 0) { throw "Command exited with $LASTEXITCODE" }
           Write-Host "PASS  $Label" -ForegroundColor Green
       } catch {
           Write-Host "FAIL  ${Label}: $_" -ForegroundColor Red
           $script:Failed++
       }
   }

   Step "cargo fmt --check" { cargo fmt --all -- --check }
   Step "cargo clippy (all targets, warnings = errors)" { cargo clippy --workspace --all-targets -- -D warnings }
   Step "cargo test (workspace)" { cargo test --workspace }

   if (Get-Command cargo-audit -ErrorAction SilentlyContinue) {
       Step "cargo audit (CI ignore list)" { cargo audit @AuditIgnores }
   } else {
       Write-Host ""
       Write-Host "note  cargo-audit not installed; skipping advisory scan" -ForegroundColor DarkGray
   }

   Write-Host ""
   if ($script:Failed -eq 0) {
       Write-Host "All required checks passed." -ForegroundColor Green
   } else {
       Write-Host "$($script:Failed) check(s) failed." -ForegroundColor Red
   }
   exit $script:Failed
   ```

   Deliberately mirrors razer's `check.sh` structure: every step runs even after a failure, so one pass shows you everything rather than only the first thing that broke. Once this exists, reference it from the README and from `AGENTS.md`, and the VS Code task becomes a one-line wrapper.

2. **Publish the invariants, then point agents at them** (section 5.2). Put the seven-item list in `SPEC.md`, commit a thin `AGENTS.md` that points there, and keep `CLAUDE.md` untracked. Right now this repo gives agents no instructions at all, and it is the repo where a wrong agent decision has the worst consequences.
3. **Add an MSRV job.** `rust-version = "1.77"` is a promise nothing checks. One job:

   ```yaml
     msrv:
       runs-on: windows-latest
       permissions:
         contents: read
       steps:
         - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
         - uses: dtolnay/rust-toolchain@29eef336d9b2848a0b548edc03f92a220660cdb8
           with:
             toolchain: "1.77"
         - run: cargo check --workspace --locked
   ```

   If it fails, either fix it or bump the declared MSRV. An unverified MSRV is worse than none.
4. **Put an expiry on the RUSTSEC ignores.** Each of the three has a written justification, which is already better than most projects. What is missing is a trigger to re-check. A monthly scheduled workflow that runs `cargo audit` *without* the ignores and opens an issue on change would tell you the day a patched `rsa` or a `zbus_xml` bump lands.
5. **Finish the deferred PE resource work with the right tool.** SPEC.md §2 defers patching the downloaded browser's own icon resources to post-v1. That is a byte-level task; the Hex Editor extension plus a golden-bytes test approach (the pattern razer already uses for HID packets) is how to do it safely. Worth borrowing your own convention across repos.
6. **Make hardening drift visible in-editor.** You have `check-hardening-drift.ps1` and a `hardening-sync.yml` workflow watching the arkenfox baseline. Add it as a VS Code task so it is one keystroke, and add a `SessionStart` hook so every agent session begins knowing whether the baseline moved. A `SessionStart` hook's stdout goes into the session context, which is exactly what you want here:

   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "pwsh -NoProfile -File ${CLAUDE_PROJECT_DIR}/check-hardening-drift.ps1",
               "timeout": 60
             }
           ]
         }
       ]
     }
   }
   ```

   Check what that script prints before wiring it up. A hook that emits fifty lines every session is a context tax, not a signal; if it is verbose, wrap it so it prints one line when nothing drifted.

**Agent brief for this repo.** When you open a session here, the framing that produces the best output is: *"this codebase's product is a verification chain; treat any change that shortens the chain as a defect until proven otherwise."* Put that sentence in `AGENTS.md`.

### 7.2 razer-control-secureblue

**Environment.** WSL2 Fedora. Build deps for the workspace:

```bash
sudo dnf install -y gcc pkg-config gtk4-devel libadwaita-devel dbus-devel systemd-devel jq
# for the run-desktop-ui skill:
sudo dnf install -y ImageMagick xdotool
```

`systemd-devel` provides libudev for `hidapi` when you build with `--features hidraw-backend`; your CI installs `libudev-dev` for the same reason on the Ubuntu runner.

**Editor.** Section 3's WSL profile, plus `"rust-analyzer.cargo.allFeatures": true` so `backend_hidraw.rs` is analysed. Use the `run: desktop UI with GTK inspector` task while working on `desktop/resources/style.css`; the Inspector's CSS editor applies changes live, which turns a rebuild-per-tweak loop into a seconds-long one.

**Gaps I would close, in priority order:**

1. **Enforce the Windows build rule in CI.** `CLAUDE.md` states core and daemon must build on the maintainer's Windows box, and nothing checks it. On Windows the GTK4, libadwaita, and ksni dependencies drop out entirely (they are `cfg`-gated to Linux/unix, and the tray's `main.rs` already compiles to a stub there), and `hidapi` is cross-platform, so this job needs no system packages:

   ```yaml
     windows-check:
       runs-on: windows-latest
       steps:
         - uses: actions/checkout@v5
         - name: Workspace still builds cross-platform
           run: cargo check --locked --workspace --all-targets
         - name: Backend type-checks on Windows too
           run: cargo check --locked -p razer-control-secureblue --features hidraw-backend
   ```

   This is the single highest-value change in this document for that repo. It converts a convention that an agent can silently break into a gate that fails loudly, and it removes the need for the `C:\src\razer-windows-check` clone from section 2.
2. **Declare the toolchain policy and MSRV.** Edition 2024 requires Rust 1.85 or newer. Add `rust-toolchain.toml` (section 4.1) and `rust-version = "1.85"` to the root `Cargo.toml` only after confirming that current compatibility. Your CI uses whatever the runner ships; a Fedora rustc on your machine may not match.
3. **Encode the licence policy as a check.** GPL-2.0-only is a hard constraint from `src/protocol.rs`'s lineage. A `deny.toml` with a `[licenses]` allow-list catches a dependency that would make the combined work non-distributable. Add `cargo deny check` to `scripts/check.sh` next to the existing optional `machete` and `audit` steps.
4. **Split `CLAUDE.md` into `AGENTS.md` plus an import,** and symlink `.agents/skills` (sections 5.2 and 5.5), so Codex works with the same understanding of the safety model that Claude has. Today a Codex session in this repo starts blind, which matters more now that Codex owns whole tasks.
5. **Add the hardware guard hook** (section 5.6) before you reach the Phase 3 milestone, not during it.
6. **Path C (COPR) is a vendoring problem, and it is now easy.** `docs/INSTALL.md` notes the Tauri-era blockers are gone and that `cargo vendor` / rust2rpm is routine with the GTK4 app. That is a well-scoped task to hand an agent with the `ci-cd-and-automation` skill: generate the vendor tarball, adjust the spec's `%prep`/`%build`, add `--offline` to the cargo invocations, and prove it with the existing Fedora container job.

**Agent brief for this repo.** *"Every client is a policy-free IPC client; every operation passes `validate_operation()`; no packet reaches hardware without a compile-time feature, a runtime flag, and (for experimental ops) an explicit opt-in. A change that makes any of those three optional is wrong even if it makes a test pass."*

**One note on your memory repo.** Keeping durable cross-session facts in the private `razer-control-memory` repo is a good pattern and I would keep it. It complements Claude Code's built-in auto memory rather than duplicating it: auto memory is machine-local, per-repository, and Claude-written (index at `~/.claude/projects/<project>/memory/MEMORY.md`, first 200 lines loaded per session), while your repo is versioned, portable across machines, and human-curated. The one thing to add is a line in `AGENTS.md` telling Codex it exists, since Codex will not know.

---

## 8. The reusable baseline

Strip the project specifics and a reusable set of foundation components remains. Use
only the components a project needs; `NEW-PROJECT.md` defines the current creation
workflow.

### 8.1 Foundation components

| File | Purpose |
|---|---|
| `PROJECT-CHARTER.md` | Purpose, first milestone, environment, data handling, non-goals, and open decisions for a new project. |
| `rust-toolchain.toml` (or equivalent) | One toolchain for you, both agents, and CI. |
| `AGENTS.md` | The shared brief: what this is, the commands, the invariants, the conventions. Committed. |
| `CLAUDE.md` | `@AGENTS.md` plus Claude-specific lines. |
| `.claude/rules/*.md` | Path-scoped rules that load only when the agent touches matching files. |
| `.claude/settings.json` | Permission allow/ask/deny and hooks. Enforcement, not guidance. |
| `.claude/skills/<name>/SKILL.md` | Procedures no model can re-derive. Symlinked into `.agents/skills/` for Codex. |
| `scripts/check.sh`, or `check.ps1` on Windows | One committed command that mirrors CI exactly. Not a VS Code task: a gate only runnable from inside an editor is invisible to CI and to both agents. |
| `.vscode/{settings,tasks,launch,extensions}.json` | Editor agrees with the gate; one-key access to the gate. |
| `deny.toml` / audit config | Licence and advisory policy as a check. |

The organising principle: **anything you would repeat to a new contributor goes in `AGENTS.md`; anything that must never happen goes in a hook or a deny rule; anything with more than three steps goes in a skill.** Context files are advice, permissions are law, skills are procedure. Most agent setups fail because they put all three in one long markdown file and then wonder why the agent ignored step 7.

### 8.2 Setup order for a new machine

`START-HERE.md` is the operational new-PC sequence. `NEW-PROJECT.md` covers a project
that does not exist yet.

1. Install VS Code, create the two Rust profiles and two General profiles, then install
   extensions in the correct Windows or Remote-WSL host.
2. `rustup` on Windows (MSVC) and inside WSL; add `rustfmt` and `clippy`.
3. Install the cargo tools from 4.2 on both sides.
4. Install the Claude Code extension and the standalone `claude` CLI (the extension bundles a private copy but does **not** put `claude` on PATH; you need the standalone install for `claude mcp add` and terminal use). Install Codex likewise, on both sides.
5. Add Context7 only if current library documentation is needed. Treat GitHub MCP as
   optional; prefer `git` and `gh` for ordinary repository work.
6. Write `~/.codex/config.toml` (5.4). The bootstrap script does this for you.
7. Install optional plugins or skills only when a real workflow requires them.
8. For each existing repository, compare current policy before adding files. For a new
   repository, write the project charter first.
9. Run the local gate, inspect the diff, and use a pull request before merging
   foundation changes.

### 8.3 Habits that matter more than configuration

Plan mode for anything touching an invariant. The gate runs on your machine, not just on the agent's claim about it. One agent per working tree, and one agent per task from start to finish. A second opinion reviews the diff, never the plan: reviewing a plan produces agreeable noise, reviewing a diff produces findings. And when you correct the same thing twice, that correction belongs in `AGENTS.md` or a rule, not in the next prompt.

---

## 9. Verify the setup actually works

Configuration that looks right and does nothing is the failure mode worth designing against. A hook with a wrong path, an extension installed on the wrong side of the WSL boundary, and an MCP server with a stale token all fail silently. Twelve minutes of checks catches all three.

### 9.1 The editor agrees with the gate

Open a `.rs` file in each repo and introduce a deliberate clippy warning, for example an unused variable. You should see it inline within a few seconds (Error Lens), and it should have the same wording as the terminal output of the gate task. If the editor is quiet but the gate fails, `rust-analyzer.check.command` is not set to `clippy`, or rust-analyzer never started. Check the language status item in the status bar.

Then run the gate itself:

```bash
./scripts/check.sh                    # razer, in the WSL window
```

```powershell
pwsh -File .\check.ps1                # Nomad, in the Windows window (or Ctrl+Shift+B)
```

Both should pass on a clean checkout. If they do not, fix that before adding agents to the picture; you cannot tell agent-caused breakage from pre-existing breakage otherwise.

### 9.2 The right extensions are on the right side

In the WSL window, open the Extensions view. Installed extensions are grouped, and the group heading says which host they belong to. rust-analyzer and CodeLLDB must appear under the WSL group, not only under Local. This is the single most common setup mistake and it presents as "rust-analyzer does nothing in my WSL project".

### 9.3 The MCP servers are connected, not merely configured

```bash
claude mcp list
```

For each server you intentionally configured, verify that it connects. A GitHub
authentication error can indicate an expired or insufficient credential. Claude's
stored authorization header is separate from GitHub CLI authentication: replace or
remove that server configuration manually as described in section 5.8. Rerunning
bootstrap does not refresh Claude's header. For Codex, verify GitHub CLI authentication
with `gh auth status --hostname github.com --active`, then start a new process through
the credential helper.

For Codex, start a session and ask it what MCP tools it has. If it lists none while the CLI sees them, you have hit the config-visibility gap noted in 5.4.

### 9.4 The guardrails actually block

Test guardrails in a disposable fixture with no hardware access, credentials or
real signing material. Never use a real hardware command or signing-key edit as a
test of whether a guardrail works: a failed guardrail would perform that action.

For the hardware hook, feed a synthetic tool-input JSON payload directly to a copy
of the hook and assert its deny decision. Include denied and allowed command
strings, malformed input and missing parser dependencies. The harness must inspect
the returned decision; it must never execute the command string in the payload.

For file permissions, create an unrelated temporary repository with a dummy file
named `nomad-release-signing-key.asc` containing only fixture text. Copy the relevant
permission rule there and test the edit against that dummy file. A failed test may
only change disposable text. Do not copy any real key into the fixture.

Verify each agent's configured controls independently in this fixture. Shared
`AGENTS.md` instructions express policy but are not proof of enforcement. Consult
the agent's current documentation and record observed behavior; do not assume that
one agent's hooks or permission rules apply to another.

### 9.5 Both agents can see their instructions

In Claude Code, run `/context` and confirm your `CLAUDE.md` appears under **Memory files**. If it does not, Claude cannot see it, whatever the file says. In Codex, ask "what does AGENTS.md tell you about this repo?" and check that the answer reflects the file rather than the code.

### 9.6 A file-by-file checklist

Per repo, confirm each exists and is in the state you intended:

| File | Committed? | Check |
|---|---|---|
| `rust-toolchain.toml` | yes, both repos | `rustc --version` inside the repo matches the pin |
| `AGENTS.md` | yes | Codex answers questions from it |
| `CLAUDE.md` | razer yes, Nomad no | appears in `/context` |
| `.claude/rules/*.md` | razer, if un-ignored | loads when you open a matching file |
| `.claude/settings.json` | your choice | the 9.4 blocks fire |
| `.claude/hooks/*` | with settings.json | executable bit set |
| `.agents/skills/` symlink | razer | `ls -l` shows a link, not a text file |
| `.vscode/*.json` | razer yes, Nomad no | `Ctrl+Shift+B` runs the gate |
| `deny.toml` | yes | `cargo deny check` passes |
| `check.sh` / `check.ps1` | yes | passes on a clean checkout, and matches CI step for step |

---

## 10. What to re-verify, and when

The original project analysis was checked on 19 August 2026. Codex setup and
configuration claims were rechecked on 28 August 2026. Treat every version-sensitive
item as something to verify again before scripting it months later.

- **Version-gated Claude Code features.** Several things cited here name a minimum version (Focus view v2.1.221, session groups v2.1.229, `/usage` attribution v2.1.174, `/import` v2.1.213). Run `claude doctor` / check your version if one is missing.
- **Codex configuration.** OpenAI's current configuration documentation confirms
  `--profile <name>`, project-scoped `.codex/config.toml` for trusted repositories,
  `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`, and the native
  Windows `[windows] sandbox = "elevated"` recommendation. Recheck the official config
  reference before adding keys not used in this guide.
- **Model names.** `model = "gpt-5.6"` is the example in OpenAI's current config docs; use whatever your plan actually exposes rather than copying the string.
- **Extension IDs.** All Rust and Git ones above are long-standing. The systemd and RPM-spec extensions are the two I did not verify as maintained. The Codex extension I would install by searching "Codex" (publisher OpenAI) in the Extensions view rather than by ID, since I could not confirm its identifier from a primary source.
- **`agent-skills` install commands.** `codex plugin marketplace add` requires Codex CLI v0.122 or later per their docs; on older releases the command was `codex marketplace add`.
- **Codex hooks.** I found no hook or programmatic-deny mechanism in Codex's documentation, which is the basis for the asymmetry in 5.7. If Codex adds one, that section should shrink considerably. Worth re-checking every few months.
- **`deny.toml` schema.** cargo-deny removed the `copyleft`, `unlicensed`, `deny`, and `allow-osi-fsf-free` keys; older blog posts still show them and will now error. The example in 4.2 uses the current schema, but run `cargo deny init` and compare if a key is rejected.

---

## Appendix A: glossary

Terms this document uses without stopping to define them.

**Agent** here means Claude Code or Codex: a tool that reads your code, makes changes, and runs commands, rather than just completing lines as you type.

**AGENTS.md / CLAUDE.md** are plain markdown files of instructions an agent loads at the start of every session. Think of them as the briefing you would otherwise repeat out loud. Codex reads `AGENTS.md`; Claude Code reads `CLAUDE.md`, and can pull in the other with an `@AGENTS.md` line.

**Cargo workspace** is a Rust project made of several crates (packages) sharing one `Cargo.toml` at the root and one `target/` build directory. Both your repos are workspaces, which is why commands carry `--workspace` or `-p <crate>`.

**cfg gating** is Rust's compile-time conditional. `#[cfg(target_os = "linux")]` code does not exist at all on Windows. It is why the razer workspace compiles on both platforms while only really running on one, and why the language server needs to be told which platform you are looking at.

**Deny rule / permission rule** is a line in Claude Code's `settings.json` saying a tool may not touch something, for example `Edit(/core/keys/**)`. Enforced by the client, so it applies whatever the model decides.

**Gate** is the one command that must pass before a change is acceptable: `./scripts/check.sh` for razer, format plus clippy plus test for Nomad. It exists so that "is this done" has an answer that is not an opinion.

**Golden bytes** are tests that pin an exact byte sequence, used in razer for the HID packets the encoder produces. If a golden-byte test fails, the encoding changed. That is either a deliberate correction with evidence behind it, or a bug, and the test's job is to make you decide which.

**Hook** is a shell command Claude Code runs automatically at a fixed moment, for example before every Bash call (`PreToolUse`) or after every edit (`PostToolUse`). Unlike an instruction in a markdown file, a hook runs regardless of what the model intends, which is why it is the right place for "never do X".

**MCP (Model Context Protocol)** is the standard that lets an agent talk to an outside service such as GitHub. An **MCP server** is one such connection. Each one costs context in every session, which is why this document recommends only two.

**MSRV** is the minimum supported Rust version a project claims to compile with, declared as `rust-version` in `Cargo.toml`.

**Permission mode** is how much an agent may do without asking. Claude Code has Plan, Manual, Auto, and Edit-automatically; Codex has Chat, Agent, and Agent (Full Access).

**Plan mode** makes Claude describe what it intends to do and wait for approval before changing anything. In VS Code the plan opens as a document you can comment on inline.

**Skill** is a folder containing a `SKILL.md`: a procedure the agent loads only when relevant. Different from an instruction file, which loads every session. Your `run-desktop-ui` is one.

**Socket activation** is systemd starting a daemon on demand when something connects to its socket, rather than keeping it running. The razer daemon works this way.

**Worktree** is a second working directory for the same git repository, on a different branch, created with `git worktree add`. Useful when you want two tasks in flight without one agent's edits landing on the other's branch.

**WSLg** is the part of WSL2 that lets Linux graphical apps display on Windows. It is how the GTK4 app appears on your screen at all, and its quirks are why the `run-desktop-ui` skill exists.

---

## Appendix B: troubleshooting

The failures that actually happen, and what each one means.

### rust-analyzer does nothing

Most often it is installed on the wrong side of the WSL boundary. Open the Extensions view in the WSL window and confirm rust-analyzer appears under the WSL group, not only under Local. If it is there, click the language status item in the status bar for its actual state; "loading" forever on a cold workspace is normal for the first minute while it builds the crate graph.

If it starts but flags GTK types as unknown in the razer repo, `rust-analyzer.cargo.allFeatures` is not set, or you opened the folder from Windows rather than through WSL.

### Builds are painfully slow in WSL

The repo is probably under `/mnt/c/`. Files there are reached across a translation layer and Cargo touches thousands of them. Move the checkout to `~/src/` inside the Linux filesystem. This is worth checking first for any "WSL is slow" complaint; it is usually the whole explanation.

### A registered WSL distribution will not start

`wsl -l -v` lists the distribution, the row reads `Stopped` and `2`, and everything
looks correct, but any attempt to run a command in it fails with
`Failed to attach disk ... ext4.vhdx` and
`Wsl/Service/CreateInstance/MountDisk/HCS/ERROR_PATH_NOT_FOUND`.

The registration and the backing virtual disk are separate. An interrupted install, or
a later cleanup of `%LocalAppData%`, leaves the registry entry pointing at a disk that
no longer exists. Confirm it:

```powershell
wsl -l -v
Get-ChildItem "$env:LOCALAPPDATA\wsl" -Recurse -Filter ext4.vhdx -ErrorAction SilentlyContinue
```

A listed distribution with no matching `ext4.vhdx` is an orphaned registration. Clear
it and reinstall:

```powershell
wsl --unregister <Distro-name>
wsl --install <Distro-name>
```

`wsl --unregister` is normally destructive: it permanently deletes the distribution and
every file inside it, with no recycle bin. It is safe **only** once you have confirmed
there is no disk to lose. Check the file listing before running it, and check the name
you are passing, because there is no undo and no confirmation prompt.

This is the reason Step 2 of `START-HERE.md` probes with `wsl -d <name> -- true`
instead of trusting the `wsl -l -v` listing. Being registered is not the same as
working, and the cheap check that only reads a listing will report success here.

### `cargo build` fails at the linking step on Windows

Missing MSVC C++ build tools. `winget install --id Microsoft.VisualStudio.2022.BuildTools -e`, and tick "Desktop development with C++" in the installer. The bootstrap script tests for this deliberately, because the error message Rust produces does not say "install Visual Studio".

### The GTK app launches but the window is blank

Under WSLg this usually means the app crashed after creating the window. The `Vulkan`, `libEGL`, and `ZINK` warnings at startup are benign software-rendering fallback and are not the cause; your own `run-desktop-ui` skill says so explicitly. Confirm the process is alive with `pgrep -f target/debug/razer-control-desktop` before debugging the rendering.

### A hook does not block anything

Three causes, in order of likelihood: the script is not executable (`chmod +x`), `jq` is not installed, or the path in `.claude/settings.json` does not resolve. A hook that fails to run does not error, it just does not block, which is why 9.4 tests it rather than trusting it. Run the script by hand with a sample JSON payload on stdin to see the real error.

### `claude` is not a recognised command

Installing the VS Code extension does not put `claude` on your PATH; the extension carries a private copy for its own panel. Install the standalone CLI as well. Same on both sides of WSL.

### An MCP server shows "Failed to connect"

For GitHub, first run `gh auth status --hostname github.com --active`. Claude stores
the header without validating it, so rerun the bootstrap after a credential change.
For Codex, use the matching `helpers/codex-with-github-mcp` launcher rather than
exporting a PAT in your shell. For any server, `claude mcp get <name>` gives more
detail than `list`.

### Claude ignores something in CLAUDE.md

First confirm it loaded: `/context` lists what is actually in the session under Memory files. If it is not there, the file is in the wrong place. If it is there and still ignored, the instruction is probably too vague or contradicts another instruction; the documentation is explicit that these files are context rather than enforcement. Anything that must happen belongs in a hook instead.

### Codex ignores a rule that Claude follows

Expected, and covered in 5.7. `.claude/rules/`, hooks, and deny rules are Claude Code features. Codex only reads `AGENTS.md`. If a rule matters for both agents, it must exist in `AGENTS.md`.

### The razer desktop crate will not compile in WSL

Missing development headers: `sudo dnf install -y gtk4-devel libadwaita-devel dbus-devel`. A `pkg-config` error naming `gtk4` or `libadwaita` is this, not a Rust problem.

### `cargo deny check` fails on a licence you did not add

A dependency pulled in a licence not on your allow-list. Read what it names, decide whether it is compatible with the project's licence, then either add it to `allow` or replace the dependency. For razer that decision is not cosmetic: GPL-2.0-only constrains what it can link against.

---

## Sources

Primary documentation consulted:

- [Use Claude Code in VS Code](https://code.claude.com/docs/en/vs-code): extension settings, permission modes, checkpoints, plugins, CLI-vs-extension differences
- [How Claude remembers your project](https://code.claude.com/docs/en/memory): CLAUDE.md scopes, the `@AGENTS.md` import pattern, `.claude/rules/`, auto memory
- [Configure permissions](https://code.claude.com/docs/en/permissions): allow/ask/deny syntax, Bash wildcard semantics, Read/Edit gitignore-style paths
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks): event names, settings.json shape, PreToolUse blocking
- [Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp): `claude mcp add` syntax, scopes, `.mcp.json`
- [Codex config basics](https://learn.chatgpt.com/docs/config-file/config-basic): config.toml locations, precedence, profiles, approvals, sandboxing, and Windows mode
- [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli): `[mcp_servers.*]` tables, transports, and environment-backed bearer tokens
- [Build skills (Codex)](https://learn.chatgpt.com/docs/build-skills.md): `.agents/skills` locations, frontmatter, invocation, `[[skills.config]]`
- [Codex IDE extension](https://learn.chatgpt.com/docs/codex/ide) and [CLI](https://learn.chatgpt.com/docs/codex/cli.md)
- [Context7](https://github.com/upstash/context7): endpoint and package name
- [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills): read at HEAD, including `docs/codex-setup.md`, `AGENTS.md`, and the 24 `skills/*/SKILL.md`
- [cargo-deny licence configuration](https://embarkstudios.github.io/cargo-deny/checks/licenses/cfg.html): current `[licenses]` keys and the removed ones

Your repositories, read at the commits named at the top: [Nomad-Launcher](https://github.com/cyph3rpuNk-dev/Nomad-Launcher) and [razer-control-secureblue](https://github.com/cyph3rpuNk-dev/razer-control-secureblue).
