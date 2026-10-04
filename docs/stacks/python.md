# Optional Python stack (uv)

```powershell
powershell -NoProfile -File .\bootstrap-windows.ps1 -Stack Python -InstallMissing
```

```bash
bash bootstrap-linux.sh --stack=python      # Linux or WSL
bash bootstrap-macos.sh --stack=python      # macOS
```

The stack installs [uv](https://github.com/astral-sh/uv) and the Python and Ruff VS
Code extensions (`ms-python.python`, `charliermarsh.ruff`). On Windows uv comes from
winget (`astral-sh.uv`). On macOS and Linux the official installer from `https://astral.sh/uv`
is downloaded completely before it runs; it installs to `~/.local/bin` and adds that
directory to your shell profile, so open a new terminal afterwards.

No system Python is installed or changed. uv manages Python versions, virtual
environments, dependencies and a committed `uv.lock` per project, which keeps projects
reproducible and independent of the operating system's Python.

Typical project start, after the charter decides on Python:

```bash
uv init --app .                 # or --lib for a library; review what it generates
uv add --dev ruff pytest
uv run ruff format --check .
uv run ruff check .
uv run python -m pytest -q
```

`new-project.sh --stack python` (or `new-project.ps1 -Stack Python`) pre-fills the gate
with the last three commands. Running pytest through `python -m` puts the project
folder on the import path, so a test can import an app module such as `main.py`; with
plain `pytest`, that import fails in the `--app` layout. pytest exits with status 5 when it collects no tests, so
add a first test before running the gate, or delete the gate's test line until then and
record that under "Open decisions" in the charter. Pin the Python version deliberately in
`.python-version` and `pyproject.toml` rather than accepting the generator's default;
check deployment and library compatibility first. Commit `uv.lock` and change it only
through uv.

Linux-first Python work (data pipelines, services, anything with containers) usually
belongs in Linux or WSL; see the environment table in NEW-PROJECT.md.
