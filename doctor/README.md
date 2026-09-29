# Development-environment doctor

Run the doctor in each environment you use, after bootstrap and whenever an agent,
MCP server or editor behaves unexpectedly. Pass the same selections you installed with:

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -Doctor -Stack Rust,Python -Wsl -ConfigureAgents
```

```bash
bash bootstrap-linux.sh --doctor --stack=rust,python --configure-agents   # Linux or WSL
bash bootstrap-macos.sh --doctor --stack=rust,python --configure-agents   # macOS
```

The doctor is deliberately read-only. It checks the operating-system boundary (native
Windows, macOS, native Linux or WSL), base tools, editor extensions, and whatever stacks,
WSL and agent configuration you select. Selections are not persisted. The Windows
doctor with `-Wsl` starts the default WSL distribution to prove it works, because a
listed distribution can have a missing disk; that starts a process but installs and
writes nothing.

It does not verify VS Code profile names, interactive Claude/Codex sign-in, live MCP
connectivity, the Windows Rust linker probe (provisioning runs that), configuration
schema, or any repository's own gate. Check those by hand:

```text
git --version
gh auth status --hostname github.com --active
claude --version && claude doctor        # if you use Claude Code
codex --version                          # if you use Codex
```

Open one VS Code window per environment you use (a Remote-WSL window for WSL) and
confirm the intended profile is active and code-running extensions show the right
install location.

Missing required tools and missing system packages are failures. Missing optional
tools, GitHub authentication and agent configuration are warnings. Exit zero is not
proof that every optional feature is ready.

To validate changes to this toolkit itself, use `scripts/check.ps1` as described in
the root README. Its mocked tests are separate from machine readiness checks.
