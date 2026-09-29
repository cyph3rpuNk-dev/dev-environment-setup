# Repository foundation templates

`new-project.ps1` and `new-project.sh` copy these into a new repository and replace
only what they know: the project name, gate command, environment and its rationale,
and (with an explicit stack choice) the gate's format, lint and test commands.
Everything else stays a visible `{{...}}` placeholder for a human decision.

Do not ask an agent to infer a runtime minimum, licence, data right, protected path,
security invariant, destructive command, release process, or production credential.

| Template | Destination | Replace |
|---|---|---|
| `foundation/PROJECT-CHARTER.md.template` | `PROJECT-CHARTER.md` | every `{{...}}`; keep unknowns under Open decisions |
| `foundation/AGENTS.md.template` | `AGENTS.md` | purpose, verified invariants, prohibitions, boundaries |
| `foundation/CLAUDE.md.template` | `CLAUDE.md` (only if Claude Code is used) | nothing; add Claude-only notes below the import |
| `foundation/check.sh.template` | `scripts/check.sh` (Linux/WSL) | `{{FORMAT_COMMAND}}`, `{{LINT_COMMAND}}`, `{{TEST_COMMAND}}` |
| `foundation/check.ps1.template` | `scripts/check.ps1` (Windows) | the same three commands |
| `foundation/README.md.template` | `README.md` | name, environment, gate command |
| `foundation/gitattributes.template` | `.gitattributes` | nothing |
| `foundation/gitignore.template` | `.gitignore` | add the stack's build output |
| `foundation/editorconfig.template` | `.editorconfig` | nothing |
| `rust/rust-toolchain.toml.template` | `rust-toolchain.toml` | channel or exact version from a documented policy |

The gate templates resolve the repository root as the parent of `scripts/`; adjust
that if you put the gate elsewhere. Each placeholder is one command, so give separate
commands separate steps and a later success cannot hide an earlier failure. Both gate
templates refuse to run while any placeholder remains, so an unfinished gate can never
report success. Run each command on its own first, then use the completed gate in CI,
VS Code tasks and agent instructions.

Add repository-specific hooks and rules only when a real invariant needs enforcement,
and repeat any critical prohibition in `AGENTS.md` so every agent sees it.

## Existing repositories

Do not overwrite established documentation or policy with a generic template.

1. Read the current README, contribution guide, CI, manifests, existing agent files,
   and local gate.
2. Identify missing pieces and contradictions.
3. Copy only a missing template whose role is not already served by another file.
4. Preserve accurate hand-written content verbatim when moving it.
5. Work on a branch, run the current gate, review the diff, and use a pull request.

See [NEW-PROJECT.md](../NEW-PROJECT.md) for the full new-project workflow.
