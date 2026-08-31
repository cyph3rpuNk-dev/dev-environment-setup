# Canonical VS Code profiles

Create four named user profiles, then paste the matching template into the profile's
user settings:

| Profile | Use for | Settings template |
|---|---|---|
| `Rust · Windows` | Nomad Launcher and Windows-native Rust work | `Rust-Windows.settings.jsonc` |
| `Rust · WSL` | razer-control-secureblue and Linux/WSL Rust work | `Rust-WSL.settings.jsonc` |
| `General · Windows` | Future Windows-native projects | `General-Windows.settings.jsonc` |
| `General · WSL` | Future Linux, data, service, and command-line projects | `General-WSL.settings.jsonc` |

The general profiles are intentionally language-neutral. Add a language extension
only after a project selects that language, and put shared project recommendations in
the repository's `.vscode/extensions.json`.

Run the corresponding bootstrap from a terminal in that profile's environment. VS
Code installs extensions separately on Windows and Remote-WSL, so the same extension
may need installing on both hosts.

Export each completed profile and keep the export in a private backup. Do not commit
profile exports. VS Code owns that format and may change it; the portable source of
truth in this folder is the profile name plus its small settings template.
