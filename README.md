# Development environment setup

Project-neutral workstation setup for Windows and optional Fedora in WSL.
Follow [START-HERE.md](START-HERE.md) for a new machine and
[NEW-PROJECT.md](NEW-PROJECT.md) for a new repository.

The default bootstrap installs base tools and general editor extensions. Rust is
opt-in with `-Stack Rust` or `--stack=rust`; agent configuration is opt-in with
`-ConfigureAgents` or `--configure-agents`. Supply selections on each run,
including check/doctor and reruns. Existing installations are never uninstalled.
These defaults replace the earlier all-in-one setup.

- [Stack profiles](docs/stacks/README.md): optional runtimes and build tools.
- [Editor profiles](profiles/README.md): portable settings, copied separately.
- [Project guides](docs/projects/README.md): optional Nomad, Razer and NCAAM workflows.

`dev-environment-setup.md` is retained as a dated project reference; its old
bootstrap commands are superseded by the current onboarding guide.

## Maintaining this toolkit

Run the offline gate from any directory:

```powershell
powershell -NoProfile -File scripts/check.ps1
# Or, on PowerShell 7 (Windows or Linux):
pwsh -NoProfile -File scripts/check.ps1
```

Use an absolute script path when outside this repository. The gate requires Git,
PowerShell 5.1+ and Bash; it uses Git for Windows Bash when installed in its standard
location. It checks PowerShell/Bash syntax, profile and embedded Claude JSON,
credential lifetime, gate failures, browser input handling, linker-probe failures,
and mocked first-run/rerun/doctor behavior. Tests use temporary fixtures and fake
credentials. They do not install software or access real agent accounts.

CI runs the same gate with Windows PowerShell 5.1, Windows PowerShell 7 and Linux
PowerShell 7. These tests do not prove that winget, Fedora packages, WSL interoperability,
or live authentication work on a fresh machine. Use the onboarding/doctor manual
checks for those integration boundaries. TOML schema and live MCP connectivity are
not validated by the offline gate.

The shared maintenance policy is [AGENTS.md](AGENTS.md). [CLAUDE.md](CLAUDE.md)
imports that policy rather than keeping a second copy. These are agent instructions,
not runtime dependencies or a security sandbox.
The filenames and import convention follow the official
[Codex instructions guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
and [Claude memory documentation](https://code.claude.com/docs/en/memory).

## Browser bridge

The WSL bridge is opt-in:

```bash
bash bootstrap-wsl.sh --install-browser-bridge
```

It requires sudo and reachable Windows PowerShell. `--no-dnf` performs no sudo
operations and cannot be combined with this option. `--check`/`--doctor` never install
the bridge. Existing custom `wslview`, browser profile files and `xdg-open` handlers
are preserved; the exact legacy bridge shipped here can be upgraded. Review any
custom bridge manually if the installer refuses to replace it.

After running the bootstrap, open a new login shell or run
`export BROWSER=/usr/local/bin/wslview` in the calling shell before browser sign-in.
The bridge supports absolute HTTP(S) URLs only.
