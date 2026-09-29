# VS Code profiles

Create only the user profiles you need, then paste the matching template into the
profile's user settings (**Preferences: Open User Settings (JSON)**):

| Profile | Use for | Settings template |
|---|---|---|
| `General · Windows` | Windows-native projects | `General-Windows.settings.jsonc` |
| `General · Linux` | Linux projects, on native Linux or in a Remote-WSL window | `General-Linux.settings.jsonc` |
| `Rust · Windows` | Windows-native Rust | `Rust-Windows.settings.jsonc` |
| `Rust · Linux` | Linux Rust, native or WSL | `Rust-Linux.settings.jsonc` |
| `General · macOS` | Projects developed on a Mac | `General-macOS.settings.jsonc` |
| `Rust · macOS` | Rust on a Mac | `Rust-macOS.settings.jsonc` |

Earlier versions called the Linux profiles `General · WSL` and `Rust · WSL`; the
settings are the same, so existing profiles need no change.

The general profiles are intentionally language-neutral. Put a project's extension
recommendations in its `.vscode/extensions.json`, and add a language extension to a
profile only after a project selects that language. Rust profiles use default Cargo
features; choose additional features per repository.

Editor profiles do not install anything. Select `-Stack`/`--stack` in the bootstrap
for toolchains, and run the Linux bootstrap from a Remote-WSL window's terminal so
extensions land on the WSL side: VS Code installs extensions separately for Windows
and each WSL distribution.

Export each finished profile to a private backup. Do not commit exports: VS Code owns
that format, and the portable source of truth here is the profile name plus its small
settings template.
