# Development environment setup

This repository maintains a cross-platform workstation setup and project-scaffolding
toolkit for Windows, macOS (Homebrew) and Linux (Fedora/RHEL via dnf, Debian/Ubuntu via
apt), with WSL as an optional Linux environment on Windows.

This policy governs maintenance of the toolkit. New projects receive their own
policy from [AGENTS.md.template](templates/foundation/AGENTS.md.template); do not
copy this repository's identity requirements into generated projects.

## Documentation map

- [README.md](README.md): toolkit overview, entry points, and maintenance commands.
- [Beginner project guide](docs/vibe-coder-project-guide.md): plain-language workflow
  and starting prompts for building with a coding agent, from a new idea or an
  existing project.
- [START-HERE.md](START-HERE.md): machine setup commands and verification.
- [NEW-PROJECT.md](NEW-PROJECT.md): project decisions and foundation setup.
- [GUIDED-SETUP.md](GUIDED-SETUP.md): agent workflow for helping a user with setup
  or an existing project; consult it for those tasks.
- [Troubleshooting](docs/troubleshooting.md): known setup failures and recovery.

## Validation

From the toolkit folder, run `powershell -NoProfile -File scripts/check.ps1` on Windows PowerShell 5.1,
or `pwsh -NoProfile -File scripts/check.ps1` on PowerShell 7. Both invoke the same
offline gate used by CI. Bash is required; Git for Windows is supported.
Report unavailable platform checks honestly. Do not claim CI passed before it runs.

The local gate checks syntax, configuration, regression fixtures, and whitespace,
and runs ShellCheck and PSScriptAnalyzer when they are installed.
CI additionally runs platform and distribution jobs and separately checks actual
commit history with `scripts/check-commit-identity.sh`. The local gate's identity
regression tests use fixtures; they do not validate this checkout's commit history.
Passing locally does not prove every CI job passed or fresh-machine setup works.

## Working changes and attribution

- Inspect the branch, working tree, and relevant diff before editing. Preserve
  unrelated changes and stage only files belonging to the requested change.
- Work on a branch for each coherent change. Commit, push, and merge only within
  the user's authorized scope; do not infer merge permission from push permission.
- For commits created in this repository, use `cyph3rpuNk-dev` as author and
  committer, with `261779228+cyph3rpuNk-dev@users.noreply.github.com` as both emails.
  GitHub-created merges may use GitHub's committer identity, as allowed by CI.
- Do not add AI co-author credits, generated-by attribution, or agent session links
  to commits or pull requests. Before pushing, inspect the commits being published
  for their author, committer, and full message. Do not rewrite existing history
  merely to change attribution without explicit authorization.
- See [docs/agents.md](docs/agents.md) for attribution settings and
  [.github/workflows/check.yml](.github/workflows/check.yml) for CI enforcement.

## Maintenance rules

- Keep Windows PowerShell 5.1 compatibility for the initial bootstrap and maintain
  the Linux/Bash implementation alongside it when changing shared behavior; this
  includes keeping `new-project.ps1` and `new-project.sh` equivalent. The Linux
  script must work on native Linux, in WSL and on macOS with its Bash 3.2; keep WSL- and
  macOS-only behavior detected, not assumed.
- Preserve LF endings. Keep templates self-contained after copying; document their
  destination and replaceable fields.
- Keep check/doctor modes free of provisioning and configuration writes. Normal
  validation uses temporary fixtures and mocked package managers, agents and auth.
- Do not run real installers, retrieve real tokens, launch hardware probes, or
  alter user/system configuration as a way of testing repository changes.
- Treat URLs and tokens as data. Never interpolate them into executable source,
  persist credentials, print them, or leave temporary process credentials behind.
- Check command results before reporting success. Stop dependent work when a
  prerequisite fails, and restrict cleanup to owned, verified temporary paths.
- Preserve custom browser handlers and existing user configuration. Update the
  guides and regression checks when changing options or configuration behavior.
- Add meaningful failure-path tests for safety or execution changes. Keep
  project-specific policy out of reusable templates. Keep unrelated personal
  preferences out of this file; document repository-wide maintenance requirements here.

## Completion report

Summarize what changed, which checks passed, and anything skipped, unavailable, or
still unresolved. State whether the work is local, committed, pushed, or merged,
with the branch, commit, or pull request where applicable. Distinguish verified
results from pending actions; a prepared publishing script is not a completed push.

`AGENTS.md` is the shared policy. `CLAUDE.md` imports it; avoid duplicating rules.
