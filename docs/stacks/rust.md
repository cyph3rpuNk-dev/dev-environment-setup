# Optional Rust stack

Select Rust explicitly on every invocation, including checks and reruns. Selection is not persisted. Running the base profile later does not uninstall existing tools.

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -Stack Rust -Check
powershell -NoProfile -File .\bootstrap-windows.ps1 -Stack Rust -InstallMissing
powershell -NoProfile -File .\bootstrap-windows.ps1 -Stack Rust -Doctor
```

Windows adds rustup, rustfmt/clippy, Cargo utilities, Rust editor extensions and a temporary linker probe during provisioning. The Visual Studio C++ workload remains a manual prerequisite if linking fails. Check mode does not compile a probe.

```bash
bash bootstrap-wsl.sh --stack=rust --check
bash bootstrap-wsl.sh --stack=rust
bash bootstrap-wsl.sh --stack=rust --doctor
```

Fedora adds gcc and pkg-config, rustup, rustfmt/clippy, Cargo utilities and Rust editor extensions. `--no-dnf` still prevents sudo; missing selected packages are reported as failures. GTK, device libraries and project-specific minimum Rust versions belong to project guides and manifests.

Both stacks offer nextest, audit, deny, bacon and typos; Fedora also includes cargo-machete. Projects decide which tools and policies their own gate requires. Choose the matching Rust editor settings from `profiles/`. Toolchain pins and minimum versions belong in each repository.
