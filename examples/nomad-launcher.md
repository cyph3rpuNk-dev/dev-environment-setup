# Nomad Launcher (optional)

> **Worked example, not setup instructions.** Written against a dated snapshot; see
> [examples/README.md](README.md) for how it maps to the current toolkit.

Select the [Rust stack](../docs/stacks/rust.md) on Windows first. The MSVC linker must pass before project builds. Install release/signing tools only if the current project requires them.

Nomad Launcher is a Windows-native repository. Its remote `main` branch is the source of truth. The setup guide is advice written against a dated snapshot and must not override newer repository code, CI, or policy.

## 1. Clone or update Nomad Launcher

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

## 2. Prove the current Nomad baseline

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

## 3. Prepare the Nomad foundation on a branch

Create a branch:

```powershell
git switch -c chore/dev-environment-foundation
```

Open this repository in the `Rust · Windows` VS Code profile. Give one agent the toolkit's `examples/two-rust-repos-analysis.md` as reference without committing that personal guide to the repository. Use this brief:

> Compare the current Nomad Launcher branch with sections 3.4, 4.1, 4.2, 5.2, 5.6, 5.7, and 7.1 of the supplied development-environment guide. Apply only foundation changes that remain valid against the current repository. Treat current code, tests, SPEC.md, SECURITY.md, CI, and release scripts as authoritative. Verify every proposed invariant against code before documenting it. Do not modify `core/src/`, `launchers/`, signing material, or release behavior. Derive any licence allow-list from `cargo deny check`; do not guess it. Keep personal settings and credentials untracked. Run the resulting repository gate, show the full diff, and stop without committing or pushing.

The intended foundation is a committed gate, a deliberate Rust toolchain policy, verified invariants in normal project documentation, a thin `AGENTS.md`, and narrowly unignored `.vscode` files. The agent must skip anything the current repository already implements differently.

Review every changed line before committing. Nomad’s verification, signing, hardening, and cleanup paths are security boundaries, not ordinary refactoring targets.

## 4. Commit through a pull request

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
