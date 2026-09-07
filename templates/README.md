# Deterministic repository foundation

Use these templates before asking an agent to add project infrastructure. Copy the
smallest applicable set, replace every `{{...}}` placeholder from verified facts or
explicit human decisions, and run the repository gate.

Do not ask an agent to infer a runtime minimum, licence, data right, protected path,
security invariant, destructive command, release process, or production credential.

## New repository copy order

1. Copy `foundation/PROJECT-CHARTER.md.template` to `PROJECT-CHARTER.md`. Decide the
   purpose, first milestone, environment, data handling, and open questions before
   selecting a stack.
2. Create the stack-owned manifest, lockfile, `.gitignore`, `.gitattributes`, and
   README from the selected toolchain's current official guidance.
3. Copy `foundation/AGENTS.md.template` to `AGENTS.md` and replace its placeholders.
4. Copy `foundation/CLAUDE.md.template` to `CLAUDE.md` if Claude Code will be used.
   Keep it tracked only when repository policy permits it.
5. Copy one gate template to `scripts/check.ps1` or `scripts/check.sh`. These
   templates resolve the repository root as the parent of `scripts/`. If the
   repository uses another destination, adjust that root calculation. Replace
   each command placeholder with one command; give separate commands separate
   steps so a later success cannot hide an earlier failure. Run each command
   independently, and use the completed gate in CI, VS Code and agent instructions.
6. For Rust repositories, add `rust/rust-toolchain.toml.template` only after choosing
   the channel or exact version from a documented compatibility policy.
7. Add repository-specific hooks and rules only when a real invariant needs
   enforcement. Repeat any critical prohibition in `AGENTS.md` so every agent sees it.

## Existing repository copy order

Do not overwrite established documentation or policy with a generic template.

1. Read the current README, contribution guide, CI, manifests, existing agent files,
   and local gate.
2. Identify missing pieces and contradictions.
3. Copy only a missing template whose role is not already served by another file.
4. Preserve accurate hand-written content verbatim when moving it.
5. Work on a branch, run the current gate, review the diff, and use a pull request.

The foundation templates contain no project-specific language or deployment policy.
Use [NEW-PROJECT.md](../NEW-PROJECT.md) for the full new-project workflow and
[optional project guides](../docs/projects/README.md) for dated project examples,
subject to verification against their current repositories.
