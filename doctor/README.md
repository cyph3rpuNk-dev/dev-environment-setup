# Development-environment doctor

Run the doctor on each build side after bootstrap and whenever an agent, MCP server,
or editor behaves unexpectedly:

```powershell
pwsh -File .\bootstrap-windows.ps1 -Doctor
```

```bash
bash bootstrap-wsl.sh --doctor
```

The doctor is deliberately read-only. It checks the operating-system boundary, core
tools and extensions for the selected stack. Include `-Stack Rust` or `--stack=rust`
to check Rust, and `-ConfigureAgents` or `--configure-agents` to inspect agent
configuration. Stack choices are not persisted. It does not verify VS Code
profile names, an interactive Claude/Codex sign-in, live MCP connectivity, the Windows
linker probe, configuration syntax/schema, or repository-specific gates. Those require the manual checks in
`START-HERE.md` and section 9 of the detailed setup guide.

Warnings are actionable diagnostics, not proof that a machine is unusable. In
particular, GitHub authentication is optional unless you need the GitHub MCP server.

Missing Windows base tools (other than optional `gh`) and missing Fedora system
packages produce failures. Missing optional tools, profile/agent checks and GitHub
authentication may remain warnings; exit zero is not proof that every feature is
ready. A startup probe may start the registered WSL distribution, but does not
install software or write configuration.

To validate changes to this toolkit itself, use `scripts/check.ps1` as described in
the root README. Its mocked tests are separate from machine readiness checks.
