# Worked examples

These are dated examples from real projects, kept to show how the toolkit's ideas
apply in practice. They are not part of machine setup, and their commands may predate
the current scripts. Current project code, manifests, policy and CI always take
precedence over them.

- [two-rust-repos-analysis.md](two-rust-repos-analysis.md): a detailed August 2026
  analysis of a Windows-native Rust project and a Linux Rust project sharing one
  machine. It is the origin of the agent guidance in [docs/agents.md](../docs/agents.md)
  and the troubleshooting entries in [docs/troubleshooting.md](../docs/troubleshooting.md).
- [nomad-launcher.md](nomad-launcher.md): bringing an existing Windows-native Rust
  repository onto the foundation.
- [razer-control-secureblue.md](razer-control-secureblue.md): the same for a Linux Rust
  repository with hardware-safety rules.
- [ncaam.md](ncaam.md): a charter-first plan for a data and prediction project, with a
  good checklist for data rights and leakage that applies to any modelling project.

Where these files mention `bootstrap-wsl.sh`, `C:\Dev-Setup`, `General · WSL` or
`Rust · WSL`, read `bootstrap-linux.sh`, your toolkit clone, `General · Linux` and
`Rust · Linux`.
