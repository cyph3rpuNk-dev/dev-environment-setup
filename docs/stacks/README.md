# Optional stack profiles

The default profile is `Base`: Git, GitHub CLI, VS Code extensions and, on Windows,
PowerShell 7. It includes no language runtime, compiler or package manager.

Select stacks explicitly on every run, including check and doctor. Selections are not
remembered, and running without a stack later never uninstalls anything.

| Stack | Windows | macOS / Linux / WSL | Guide |
|---|---|---|---|
| Rust | `-Stack Rust` | `--stack=rust` | [rust.md](rust.md) |
| Python (uv) | `-Stack Python` | `--stack=python` | [python.md](python.md) |
| Both | `-Stack Rust,Python` | `--stack=rust,python` | |

Other languages: choose a runtime in the project charter and follow its current
official installation guidance. Editor settings in `profiles/` are separate from stack
selection; copying editor settings does not install a runtime.

Stacks install tools, not project policy. Minimum versions, toolchain pins, lint rules
and which checks the gate requires belong in each repository.
