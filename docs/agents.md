# Working with coding agents

This toolkit supports Claude Code and Codex. Neither is required. This page explains
the defaults `-ConfigureAgents` / `--configure-agents` create and how to keep one
project policy that both agents follow.

Agent features change quickly. Recheck the official documentation before relying on
a version-sensitive detail: <https://code.claude.com/docs> and
<https://github.com/openai/codex>.

## The organising principle

- Anything you would tell a new contributor goes in `AGENTS.md`.
- Anything that must never happen goes in an enforced control: a hook, a permission
  deny rule, or better, a build that does not contain the capability at all.
- Anything with more than a few steps goes in a skill.

Instruction files are advice, permissions are law, skills are procedure. Setups fail
when all three live in one long Markdown file and the agent skips step 7.

## One policy file, two readers

`AGENTS.md` is the canonical project policy. Codex reads it directly. Claude Code reads
`CLAUDE.md`, so `CLAUDE.md` starts with `@AGENTS.md` and adds only Claude-specific
material. The scaffolder creates both this way. Use the import rather than a symlink:
symlinks need Developer Mode or administrator rights on Windows.

Never put a critical rule only in `CLAUDE.md`, `.claude/rules/`, a hook or a personal
note. Codex does not read those, so a rule enforced for one agent is at most guidance
for the other. If a prohibition matters, state it bluntly in `AGENTS.md` as well.

Do not ask an agent to invent security invariants, supported platforms, data rights,
minimum runtime versions, licence allow-lists, release credentials or destructive
commands. Those are human decisions recorded in the charter.

## What the toolkit's defaults do

Created only when the file does not already exist; existing files are left alone.

**Codex** (`~/.codex/config.toml`): `approval_policy = "on-request"` asks at permission
boundaries; routine workspace commands can run without individual approval.
The defaults also set `sandbox_mode = "workspace-write"`, high reasoning effort, and the
Context7 documentation server. On Windows it adds `[windows] sandbox = "elevated"`.
Do not set approvals to `never` on a repository where a command can touch hardware,
production data or signing keys. For a read-only second-opinion pass, create
`~/.codex/review.config.toml` with `sandbox_mode = "read-only"` and run
`codex --profile review`.

**Claude Code** (`~/.claude/settings.json`): no global allow rules, and deny rules
that stop Claude's file tools reading `.env` and `.env.*` files, `.pem`, `.key`,
`.pfx` and `.p12` files, `~/.gnupg` and `~/.ssh`. A `Read` deny also blocks editing the
same path. These rules are a safeguard against accidental reads, not an isolation
boundary: a deny rule applies to the tool it names, so it does not stop every way of
reading a file (a shell command, for example). Keep real secrets out of project folders
where you can. `Read(**/.env.*)` also hides `.env.example`; remove that rule if you want
the agent to read example files. Put build, test and project-script permissions in
each repository's `.claude/settings.json` after reviewing that repository's side
effects. If your settings file already exists, merge this block by hand:

```json
{
  "permissions": {
    "deny": ["Read(**/.env)", "Read(**/.env.*)", "Read(**/*.pem)", "Read(**/*.key)",
             "Read(**/*.pfx)", "Read(**/*.p12)", "Read(~/.gnupg/**)", "Read(~/.ssh/**)"]
  }
}
```

**Commit and pull request attribution.** By default Claude Code adds a
`Co-Authored-By:` line naming the model to the commits it creates, and a note to pull
request descriptions. Commits and pull requests made from claude.ai web or Remote Control
sessions also get a `Claude-Session:` link. GitHub shows a co-author on the commit, and
the account can appear among the repository's contributors. The toolkit leaves this
alone, because whether an AI is credited is your decision. To turn it off, add this to
`~/.claude/settings.json` (all your projects) or to a repository's
`.claude/settings.json` (that repository, for everyone who opens it), merging it into the
file if one exists:

```json
{
  "attribution": { "commit": "", "pr": "", "sessionUrl": false }
}
```

An empty string hides that attribution, and `"sessionUrl": false` omits the session
link. Use this object form: older versions reject `"attribution": false`, and the older
`includeCoAuthoredBy` setting is deprecated. It affects new commits only; existing
history keeps its lines unless you rewrite it. After the agent's next commit, confirm
with `git log -1 --format=%B`. This toolkit has not verified whether Codex adds similar
lines, so read the message of any commit it makes before you push.

In the VS Code extension's user settings, starting in plan mode
(`claudeCode.initialPermissionMode: "plan"`) is worth it for repositories where a wrong
edit is a security regression.

## Turning rules into enforcement

`CLAUDE.md` is context, not enforcement. For a rule that must hold, use one of these,
strongest first:

1. **Remove the capability.** If a dangerous path only exists behind a build feature
   or flag, leave it out of the normal development loop. No agent can call code that
   is not in the binary, and this works for every tool.
2. **Permission rules** in the repository's `.claude/settings.json`, for example
   `"deny": ["Edit(/keys/**)"]` or `"ask": ["Bash(git push *)"]`. Paths starting with
   `/` are anchored at the project root.
3. **Hooks**: a `PreToolUse` command that inspects the tool input and returns a deny
   decision. A hook that is not executable, or whose parser (such as `jq`) is missing,
   fails silently and blocks nothing.

Test a guard only in a disposable fixture: feed it a synthetic tool-input payload and
check the decision. Never test it by running the real dangerous command; if the guard
fails, the action happens.

Codex has no equivalent of Claude's hooks or path rules in this setup, so keep its
approval policy on `on-request` and keep the prohibition in `AGENTS.md`.

## MCP servers: keep the surface small

Every connected server costs context in every session. Prefer ordinary `git` and `gh`
for repository work.

- **Context7** (current library documentation) is added by `-ConfigureAgents`. It is
  most useful when a project pins fast-moving libraries.
- **GitHub MCP** is optional. For Codex, run the bootstrap after `gh auth login`; when
  creating a new config, it adds a server entry that reads the token from
  `GITHUB_MCP_PAT`. Existing config files are preserved without parsing or appending;
  review and merge the entry below manually if needed. Launch Codex
  through `helpers/codex-with-github-mcp.ps1` or `.sh`, which fetches the token from
  GitHub CLI and passes it to Codex in its environment instead of writing it to a file.
  Codex and every command it runs can read that token, and it carries your full GitHub
  CLI access (usually every repository you can reach, plus workflows if you granted that
  scope). Use the helper only for sessions that need GitHub MCP; start Codex normally
  otherwise. Claude's documented GitHub MCP setup stores a
  personal access token in its user-scoped configuration, so the toolkit never does it
  automatically. If you accept that, use a fine-grained token limited to the needed
  repositories and remove or rotate it when finished:

  ```bash
  claude mcp add --transport http --scope user github https://api.githubcopilot.com/mcp/ \
    --header "Authorization: Bearer <fine-grained-token>"
  claude mcp list
  ```

Never put a token in `~/.bashrc`, a persistent Windows user variable or a repository.

For an existing Codex config, merge this table only if an equivalent GitHub server
entry is not already present. Keep existing customization and never duplicate a table:

```toml
[mcp_servers.github]
url = "https://api.githubcopilot.com/mcp/"
bearer_token_env_var = "GITHUB_MCP_PAT"
```

## Habits that matter more than configuration

- One agent owns a task from investigation to a passing gate, and only one agent edits
  a working tree at a time. Use `git worktree add` for parallel tasks.
- Plan mode for anything touching an invariant.
- Run the gate yourself. Agents are good at declaring victory.
- For a diff that touches an invariant, have the other agent review the **diff** (not
  the plan) with a specific brief, and ask it to name the weakest points it considered.
  Feed findings back as claims to verify, not orders.
- When you correct the same thing twice, the correction belongs in `AGENTS.md`.

## Check that it works

- Claude Code: `/context` lists `CLAUDE.md` under memory files; `claude mcp list` shows
  each server you meant to configure as connected.
- Codex: ask what `AGENTS.md` says about the repository and confirm the answer comes
  from the file; `/status` shows the sandbox and approval policy.
- Guards: test in a fixture as described above.
