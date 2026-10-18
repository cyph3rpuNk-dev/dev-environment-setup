# Predictable, lightweight setup

The default `Minimal` / `minimal` toolset keeps the base editor extension and the
selected stack's language extensions. Optional Rust utilities and extra editor
extensions require `-Toolset Recommended` / `--toolset=recommended`. Source builds
of optional utilities require a separate `-AllowSourceBuilds` /
`--allow-source-builds` choice. Reruns preserve installed tools; this change does
not uninstall tools or extensions. No container engine or additional VM is needed.

## Read-only diagnostics

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -Doctor -Stack Rust
powershell -NoProfile -File .\bootstrap-windows.ps1 -Doctor -Wsl -Distribution Ubuntu-24.04
powershell -NoProfile -File .\bootstrap-windows.ps1 -Doctor -Signing -GpgPath "C:\Program Files\GnuPG\bin\gpg.exe"
```

Doctor reports selected executable paths, available alternatives and version probe
results. Masking functions/aliases are reported without executing them for a version
probe. Signing diagnostics are optional and run only `gpg --version`: no keys,
passphrases, signatures or credentials are read. The GPG override applies only to
that probe; use an explicit path in the project's signing command too. A successful
version probe does not prove signing readiness or target runtime compatibility.
Report-only Rust probes use a neutral directory with automatic installation disabled,
including for older Rustup versions. They inspect the machine toolchain rather than
installing or validating a project's pin.

With more than one WSL distribution, select one explicitly; doctor will not choose
an arbitrary entry. It starts the selected distro to run `true`, and does not change
the default distro, networking, resource settings or browser handlers. It checks
only the host side; run the Linux doctor inside the chosen distro as well:

```bash
bash bootstrap-linux.sh --doctor --stack=rust --project-path="$HOME/src/my-tool"
bash bootstrap-linux.sh --doctor --signing --gpg-path=/usr/bin/gpg
```

The project directory must exist. Doctor resolves its real location and warns about
Windows drive mounts in WSL, including custom automount roots. Windows paths selected
for Linux build tools are also reported. The Windows VS Code launcher is an expected
exception; its version is not probed in WSL because even that can install the server.
Keep Linux builds on the
Linux filesystem and Windows builds on Windows, with separate build outputs.
Path warnings are diagnostics, not an exhaustive filesystem or executable audit.

## Project reproducibility

Scaffolding accepts optional exact `X.Y.Z` versions: `-RustVersion` /
`--rust-version` for Rust, or `-PythonVersion` / `--python-version` for Python.
Only the matching stack accepts each option. These create project-local pin files;
they do not install tools, validate upstream version availability or set global
defaults. Versionless scaffolding remains available for undecided projects.

Generated Rust lint/test commands use `--locked`; Python checks use
`uv run --locked`. Initialize the language project, review compatibility and resolve
dependencies deliberately before running the gate. Commit the pin and lockfiles.
Keep CI on the same versions and commands. Tool pins constrain versions; they do
not promise bit-for-bit reproducible release binaries or cover unpinned system SDKs.

See [Rust](stacks/rust.md), [Python](stacks/python.md) and
[troubleshooting](troubleshooting.md) for prerequisites and recovery guidance.

## Bounded downloads and setup receipts

Linux/macOS installer-script downloads use a 15-second connection timeout, a
180-second per-attempt limit and two retries for curl's transient error classes,
with a 400-second retry window. Only a completed download is executed, once. The
window is not a hard overall deadline for the final attempt or the installer. This
does not retry installers, bypass package-manager locks, or establish authenticity
beyond the existing HTTPS source. Partial scripts are removed rather than cached.
Windows keeps winget's error output visible and never retries an installer itself.

An install run can optionally write a new `-ResultFile <path>` / `--result-file=<path>`
in an existing directory. Receipts contain stage outcomes only, not console output,
authentication details or secrets. Existing filenames are refused. Check/doctor
modes refuse this option and write no receipts. Receipts can be incomplete after
power loss or forced termination; they are diagnostic records, not resume programs.
Rerun the same selections in a fresh terminal: live tool/package/config checks
decide which work is still needed. A receipt is never trusted to skip verification.
Optional auxiliary-tool versions and system package versions remain outside a
project's dependency lockfile.

## Optional project prerequisites and maintenance helpers

Pass `-MaintenanceHelpers` / `--maintenance-helpers` when scaffolding to add
`dev-requirements.tsv`, `scripts/check-project.*`, `scripts/manage-artifacts.*` and
an initially disabled `scripts/run-workflow.*`. Only the platform's script variant
is copied. They are self-contained in the new project and are not added to its gate
automatically. Existing projects can copy these reviewed files individually.

The requirements file starts with `# devsetup-requirements-v1`. Each non-comment
row has exactly three tab-separated fields: kind, value and scope (`all`, `windows`
or `unix`). Supported kinds are `command`, `rust-target`, `pkg-config`, `file` and
`windows-sdk`. Names are treated as data; arbitrary command lines are refused.
`file` paths stay relative to the project. A Windows SDK requirement checks the
specified Windows 10/11 SDK's header and x64 import library, not its integrity or
other architectures. Merely finding a command does not prove its version or use.
No declared requirements means readiness remains unknown.

```powershell
powershell -NoProfile -File scripts/check-project.ps1
# Explicitly compile this project's Rust code after prerequisites pass:
powershell -NoProfile -File scripts/check-project.ps1 -SmokeBuild -Target x86_64-pc-windows-msvc
```

```bash
bash scripts/check-project.sh
bash scripts/check-project.sh --smoke-build --target x86_64-unknown-linux-gnu
```

Read-only checks install nothing. The explicit smoke build requires Cargo.toml,
Cargo.lock and a target, runs `cargo build --locked`, and can execute the project's
build scripts and fetch locked dependencies. It is separate from doctor/check mode
and from runtime compatibility testing. Doctor accepts a project path to run only
the prerequisite checks.

## Test workflow template

Before enabling the workflow, review and implement its start, collect and restore
hooks. Restore must be safe to retry for that project's owned changes. Start makes
a unique run under `artifacts/runs/`; collection requires a started run, and restore
remains available after failed start/collection. Wrong-order phases fail without
claiming success. A lock prevents simultaneous phases. A process crash may leave a
lock: inspect ownership and confirm the producer/helper has stopped before manually
resolving it. The helper never guesses that a stale lock is safe to remove.

Each run records its helper hash, shell version, Git revision/dirty status when
available, and phase state. Repositories without a first commit are labelled
`unborn-or-unavailable`. It does not hash the whole working tree or establish
the authenticity of results. Collection must verify the producer has closed its
logs, copy those closed files into the run, then hash the copied bytes. Never hash
a live log and later copy different bytes. The template deliberately refuses to
collect until the project supplies this logic. It performs no browser, firewall,
registry or remote-control operations on its own.

## Artifact retention and cleanup

Use separate categories: `cache` for rebuildable output, `runs` for disposable test
work, `evidence` for retained reviewed results, and `releases` for release assets.
Creating an entry writes an ownership marker and returns its exact directory:

```powershell
powershell -NoProfile -File scripts/manage-artifacts.ps1 -Action Create -Category cache
powershell -NoProfile -File scripts/manage-artifacts.ps1 -Action Clean -Category cache -Id <printed-id>
# Add -Apply to that same selection only after reviewing the preview.
```

```bash
bash scripts/manage-artifacts.sh --action create --category cache
bash scripts/manage-artifacts.sh --action clean --category cache --id <printed-id>
# Add --apply to that same selection only after reviewing the preview.
```

Point a build tool at that returned cache directory explicitly if appropriate; no
global cache setting is changed. Move selected, closed results into a separately
created evidence entry before cleaning disposable runs. Cleanup requires an exact
ID and matching marker, previews by default and rejects linked paths, special
files, repository metadata, tracked files, workflow locks and unrestored workflows. It never removes
the evidence/release categories or category roots. The scaffolder ignores the
whole local `artifacts/` tree in Git to prevent accidental evidence publication.

Markers prevent routine mistakes; they are not authentication against another
process that can rewrite the filesystem. Do not clean during concurrent writes.
Deletion is ordinary filesystem removal, not secure erasure. Retained evidence and
releases need a separate backup policy. Existing target/build directories are not
adopted or deleted automatically.
