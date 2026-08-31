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
tools, Rust components, agent configuration, GitHub CLI authentication, and the
extensions detectable from the command line. It does not verify the four VS Code
profile names, an interactive Claude/Codex sign-in, live MCP connectivity, the Windows
linker probe, or repository-specific gates. Those require the manual checks in
`START-HERE.md` and section 9 of the detailed setup guide.

Warnings are actionable diagnostics, not proof that a machine is unusable. In
particular, GitHub authentication is optional unless you need the GitHub MCP server.
