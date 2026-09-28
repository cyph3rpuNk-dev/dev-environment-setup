# razer-control-secureblue (optional)

> **Worked example, not setup instructions.** Written against a dated snapshot; see
> [examples/README.md](README.md) for how it maps to the current toolkit.

Select the [Rust stack](../docs/stacks/rust.md) inside Fedora first. Confirm current project prerequisites before installing additional packages. The historical dependency set included `gtk4-devel libadwaita-devel dbus-devel systemd-devel jq ImageMagick xdotool`; these are deliberately excluded from the base and Rust bootstraps. Verify the Rust minimum against the current manifest (the historical guide required 1.85 for edition 2024).

razer-control-secureblue is a Fedora/Linux repository. Keep its canonical checkout inside the WSL filesystem, not under `/mnt/c`.

## 1. Clone or update razer-control-secureblue

Inside Fedora:

```bash
mkdir -p ~/src
git clone https://github.com/cyph3rpuNk-dev/razer-control-secureblue.git ~/src/razer-control-secureblue
cd ~/src/razer-control-secureblue
git status
```

If it is already cloned:

```bash
cd ~/src/razer-control-secureblue
git status
git fetch origin
git switch main
git pull --ff-only
```

Stop if `git status` reports work you do not recognize.

## 2. Prove the current Razer baseline

Run the repository’s existing gate:

```bash
./scripts/check.sh
```

If it is not executable, inspect it before running `bash scripts/check.sh`. Do not change file permissions until you know whether the repository intended it to be executable.

Record pre-existing failures.

## 3. Prepare the Razer foundation on a branch

```bash
git switch -c chore/dev-environment-foundation
```

Open the repository from a Remote-WSL window using the `Rust · Linux` profile. Use this brief with one agent:

> Compare the current razer-control-secureblue branch with sections 3.4, 4.1, 4.2, 5.2, 5.5, 5.6, 5.7, and 7.2 of the supplied development-environment guide. Apply only foundation changes that remain valid against the current repository. Preserve the existing `CLAUDE.md` content verbatim when moving shared policy into `AGENTS.md`; do not summarize or regenerate it. Treat current code, tests, CI, and documentation as authoritative. Do not modify `src/`, `desktop/`, or `tray/`, except for a reviewed `rust-version` declaration if current compatibility proves it. Run `cargo deny check` before choosing licences. Do not run a real hardware backend or any command that can write to the embedded controller. Run the final repository gate, show the full diff, and stop without committing or pushing.

Test hardware guards only with synthetic tool-input payloads in disposable fixtures; never execute hardware-writing commands to test a guard. Codex does not inherit Claude-specific enforcement, so the same prohibition must appear in `AGENTS.md` and command approval must stay enabled.

## 4. Commit through a pull request

After the gate passes and you approve the diff:

```bash
git add --all
git diff --staged
git commit -m "chore: add development environment foundation"
git push -u origin chore/dev-environment-foundation
gh pr create --fill
```

Wait for GitHub Actions and review the pull-request diff before merging.

---
