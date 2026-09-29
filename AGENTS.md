# Development environment setup

This repository maintains a cross-platform workstation setup and project-scaffolding
toolkit for Windows, macOS (Homebrew) and Linux (Fedora/RHEL via dnf, Debian/Ubuntu via
apt), with WSL as an optional Linux environment on Windows. It is not application source. Start with
`README.md` for maintenance and `START-HERE.md` for workstation onboarding.

## Validation

Run `powershell -NoProfile -File scripts/check.ps1` on Windows PowerShell 5.1,
or `pwsh -NoProfile -File scripts/check.ps1` on PowerShell 7. Both invoke the same
offline gate used by CI. Bash is required; Git for Windows is supported.
Report unavailable platform checks honestly. Do not claim CI passed before it runs.

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
  project-specific policy out of reusable templates and personal preferences out
  of this file.

`AGENTS.md` is the shared policy. `CLAUDE.md` imports it; avoid duplicating rules.
