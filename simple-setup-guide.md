# Quick setup

Follow [START-HERE.md](START-HERE.md) for the full sequence.

1. Check Windows with `powershell -NoProfile -File .\bootstrap-windows.ps1 -Check`.
2. Install missing base tools with `powershell -NoProfile -File .\bootstrap-windows.ps1 -InstallMissing`, reopen the terminal, and rerun as needed.
3. If Linux work requires it, prepare Fedora in WSL and run `bash bootstrap-wsl.sh --check`, then `bash bootstrap-wsl.sh`.
4. Choose optional [stack profiles](docs/stacks/README.md) and [editor settings](profiles/README.md).
5. Configure optional agents with `-ConfigureAgents` or `--configure-agents` only if wanted.
6. Run doctor using the same selected options and review the reported manual checks.
7. Use [NEW-PROJECT.md](NEW-PROJECT.md) or an optional [project guide](docs/projects/README.md).

Base setup does not install Rust, project libraries or agent settings. Stack choices must be supplied on every run and do not uninstall existing software.
