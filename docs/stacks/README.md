# Optional stack profiles

The default profile is `Base` on Windows and `base` on Fedora. It includes no language runtime, compiler or Cargo utilities.

- [Rust](rust.md): explicitly selected Windows/MSVC or Fedora tooling.
- Other languages: choose a runtime from the project charter and follow its current official installation guidance. No other automated stack profiles exist yet.

Editor settings in `profiles/` are separate from bootstrap stack selection. Copying editor settings does not install a runtime.
