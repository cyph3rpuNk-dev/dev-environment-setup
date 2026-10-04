# Optional Rust stack

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -Stack Rust -Check
powershell -NoProfile -File .\bootstrap-windows.ps1 -Stack Rust -InstallMissing
powershell -NoProfile -File .\bootstrap-windows.ps1 -Stack Rust -Doctor
```

Windows adds rustup (winget), rustfmt and clippy, Cargo utilities, Rust editor
extensions, and a temporary linker probe during provisioning. The probe compiles a
throwaway crate because a missing MSVC linker only shows up at link time, with an
error that does not say "install Visual Studio". If it fails, install
`Microsoft.VisualStudio.2022.BuildTools` with the **Desktop development with C++**
workload; that large selection stays a manual, reviewed step. Check mode does not
compile the probe.

```bash
bash bootstrap-linux.sh --stack=rust --check
bash bootstrap-linux.sh --stack=rust
bash bootstrap-linux.sh --stack=rust --doctor
```

Linux adds a C compiler and pkg-config (`gcc pkg-config` on Fedora,
`build-essential pkg-config` on Debian/Ubuntu), rustup from <https://rustup.rs>, rustfmt
and clippy, Cargo utilities and Rust editor extensions. The rustup installer is
downloaded completely before it runs, and it adds `~/.cargo/bin` to your shell
profile, so open a new terminal afterwards. `--no-sudo` still prevents package
installation; missing selected packages are reported as failures.

On macOS, `bash bootstrap-macos.sh --stack=rust` uses the same rustup installer and adds
`pkgconf` with Homebrew. Rust links with Apple's Command Line Tools; if they are
missing, the bootstrap fails with `xcode-select --install`, which opens a system dialog
and is left to you.

When Rust is selected, check and doctor require both rustfmt and Clippy. Missing
components or a failed component query make readiness fail. These checks do not
install anything; they use the machine toolchain from a neutral directory with
automatic installation disabled. A broken compiler is reported first, without
counting missing components again.

Every platform offers cargo-nextest, cargo-audit, cargo-deny, bacon and typos; Linux and macOS
also includes cargo-machete. They are installed with `cargo-binstall` (prebuilt
binaries) when possible and built from source otherwise.

`new-project.sh --stack rust` (or `new-project.ps1 -Stack Rust`) pre-fills the gate with
`cargo fmt`, and with `cargo clippy` and `cargo test` run with `--locked`, so a
`Cargo.lock` that no longer matches `Cargo.toml` fails the gate instead of being
rewritten. Create the lockfile with `cargo generate-lockfile` after `cargo init` and
commit it. A library that deliberately does not commit `Cargo.lock` should drop
`--locked` from its gate and record that decision in the charter.

Projects decide which tools and policies their gate requires. Add
`rust-toolchain.toml` (template in `templates/rust/`) only after choosing a channel or
exact version from a documented compatibility policy, and use the matching Rust
editor settings from `profiles/`. System libraries a particular project needs (GTK,
udev and so on) belong in that project's README, not in this stack.
