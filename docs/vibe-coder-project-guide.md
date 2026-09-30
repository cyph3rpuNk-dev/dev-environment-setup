# Starting a project with the development-environment toolkit

For a vibe coder—someone who describes what they want and lets a coding agent implement it—this toolkit provides a structured starting process. **It prepares the development environment and creates the project's foundation; the coding agent then builds the actual product.**

## 1. Start with your idea

Get the toolkit using the [README](../README.md#get-the-toolkit), then open your coding agent in the toolkit folder and give it this prompt:

> Follow GUIDED-SETUP.md to help me create a new project. My idea is: [describe your idea]. I'm a beginner, so ask questions in plain language, one at a time. Check my development environment before installing anything. Help me define a small first version, create the project, and verify it works. Ask before installing software, committing, pushing, or creating anything on GitHub. Use my chosen Git identity for authorized commits, and confirm my preference for AI co-author attribution before the first commit.

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

## Where to find the detailed instructions

- [START-HERE.md](../START-HERE.md) explains how to prepare and verify your computer.
- [NEW-PROJECT.md](../NEW-PROJECT.md) covers project decisions, scaffolding, and the first useful version.
- [GUIDED-SETUP.md](../GUIDED-SETUP.md) tells your coding agent how to walk you through those steps.

This guide explains the workflow. Use those documents for setup commands and detailed procedures. Once your project exists, its own charter, agent rules, and README guide ongoing development.
