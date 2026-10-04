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
WSL and agent configuration you select. It also reports whether your global Git
commit name and email are set and whether the email is a GitHub private (noreply)
address, without printing either value. Selections are not persisted. The Windows
doctor with `-Wsl` starts the default WSL distribution to prove it works, because a
listed distribution can have a missing disk; that starts a process but installs and
writes nothing.

Inside WSL, check and doctor modes skip invoking the code launcher: even listing
extensions can install or replace VS Code Server. Verify remote extensions in a
connected WSL editor window. A skipped listing is reported explicitly, and the
Rust doctor reuses the existing listing rather than invoking the editor again.

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
tools, GitHub authentication, Git commit identity and agent configuration are warnings. Exit zero is not
proof that every optional feature is ready.

Selecting Python makes uv required; selecting Rust requires a working compiler
version probe, including a compiler executable on PATH. Rust check/doctor probes
disable rustup automatic installation for the duration of each command, then restore
the caller setting. A missing project-pinned toolchain is reported as unavailable;
install it deliberately outside check/doctor mode. An executable on PATH that fails
its version command is a failure.
The Linux base setup also requires awk for project templates and installs gawk on
supported Linux distributions when no awk command is available.

To validate changes to this toolkit itself, use `scripts/check.ps1` as described in
the root README. Its mocked tests are separate from machine readiness checks.
