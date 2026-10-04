# Starting a project with the development-environment toolkit

For a vibe coder—someone who describes what they want and lets a coding agent implement it—this toolkit provides a structured starting process. **It prepares the development environment and creates the project's foundation; the coding agent then builds the actual product.**

## 1. Start with your idea

Get the toolkit using the [README](../README.md#get-the-toolkit), then open your coding agent in the toolkit folder and give it this prompt:

> Follow GUIDED-SETUP.md to help me create a new project. My idea is: [describe your idea]. I'm a beginner, so ask questions in plain language, one at a time. Check my development environment before installing anything. Help me define a small first version, create the project, and verify it works. Ask before installing software, committing, pushing, or creating anything on GitHub. Use my chosen Git identity for authorized commits, and confirm my preference for AI co-author attribution before the first commit.

Already have a project, or want your own version of someone else's? See [Start from an existing project](#start-from-an-existing-project) instead.

## 2. Turn the idea into a concrete project

The agent asks what the product should do, who will use it, where it will run, and whether it handles sensitive information.

Those answers determine:

- Whether development belongs on Windows, Linux/WSL, or macOS.
- Which language and tools are appropriate.
- What the first useful version should include.
- Which decisions still need your input.

The toolkit directly supports Rust and Python setup. Other languages require additional setup using their official instructions.

## 3. Check your machine and create the foundation

The agent runs the appropriate check mode, explains missing tools, and helps install what the project needs.

Then the scaffolder creates a separate project folder—normally under `%USERPROFILE%\src` for Windows projects, or `~/src` on macOS, Linux, or inside WSL—with:

| File | What it does for you |
|---|---|
| `PROJECT-CHARTER.md` | Records what you're building, its scope, and open decisions. |
| `AGENTS.md` | Gives coding agents the project's rules and boundaries. |
| `CLAUDE.md` (optional) | Lets Claude load the shared project rules. |
| `README.md` | Explains the project and how to work on it. |
| `scripts/check.*` | Provides one command for the selected formatting, linting, and tests. |
| Git/editor configuration | Establishes consistent file handling and excludes common local files. |

**At this point, you have the foundation for your project.** Language initialization, application code, meaningful tests, and CI still need to be added.

## 4. Build one small feature at a time

Open the new project folder in your editor and start the agent there. A useful request is:

> Read the charter and project rules. Build the smallest working version of [feature]. Explain any decisions you need from me, add meaningful tests, run the project checks, and show me how to try it. Don't commit or push yet.

Your development loop becomes:

**Describe a feature → agent builds it → checks run → you try it → approve the change.**

Passing checks means the configured checks passed. You still need to try the product and confirm it does what you intended.

**Your main job is to explain the desired behavior, answer product questions, and review the result.**

## Start from an existing project

The same toolkit can take over a project that already exists on GitHub: one you built without this process, or someone else's project you want to make your own version of. The agent reviews the whole repository before changing anything, and the findings become the plan.

**Your own project.** Open your coding agent in the toolkit folder and send:

> Follow GUIDED-SETUP.md Step 5 to bring my existing project into order: [GitHub URL]. I'm a beginner, so ask questions in plain language, one at a time. Before changing anything, clone it into a new folder and review the whole repository. Report what it does and how it works, its design patterns, and its bugs, security issues and possible improvements. Give each the file and line, the severity, and whether you confirmed it or are inferring it, and tell me what you could not run or check. Then propose a plan of small changes. Work on a branch, add a test for each fix, and ask before committing, pushing or opening a pull request.

**Your own version of someone else's project.** Send:

> Follow GUIDED-SETUP.md Step 5 to help me make my own version of [GitHub URL]. First check its licence: tell me in plain words what it allows and requires, and stop if there is no licence. Then clone it into a new folder and review the whole repository: what it does and how it works, its design patterns, and its bugs, security issues and possible improvements. Give each the file and line, the severity, and whether you confirmed it or are inferring it, and tell me what you could not run. Recommend whether to fork it or start a new repository, and which fixes are worth offering back to the original. Then build the improvements in small steps, each with a test. Ask before committing, pushing or creating anything on GitHub.

What to expect:

- **The licence comes first.** It decides whether you may make your own version at all. With no licence, you may read the code but not reuse it; ask the author. Permissive licences such as MIT, BSD or Apache let you build on it if you keep the original copyright and licence notices. The GPL requires a version you share with others to stay under the GPL, with its source available; the AGPL extends that to people who use it over a network. The agent explains the licence it finds; the decision is yours, and this guide is not legal advice.
- **A review is a starting list, not a guarantee.** The first review will miss things. Expect more issues to surface as you build, and ask for another review after large changes.
- **Your own version stops receiving the original's fixes** unless you bring them in. If a fix would help the original project too, offering it back is often worth more than keeping a separate copy.
- **The foundation is added, not imposed.** The agent adds a charter, agent rules and one check command only where the project lacks them, and keeps what already works.

From there, the loop is the same as in [step 4](#4-build-one-small-feature-at-a-time): one small, tested change at a time, reviewed by you.

## Where to find the detailed instructions

- [START-HERE.md](../START-HERE.md) explains how to prepare and verify your computer.
- [NEW-PROJECT.md](../NEW-PROJECT.md) covers project decisions, scaffolding, and the first useful version.
- [GUIDED-SETUP.md](../GUIDED-SETUP.md) tells your coding agent how to walk you through those steps, including taking over an existing project (Step 5).

This guide explains the workflow. Use those documents for setup commands and detailed procedures. Once your project exists, its own charter, agent rules, and README guide ongoing development.
