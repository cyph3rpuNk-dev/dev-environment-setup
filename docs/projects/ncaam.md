# NCAAM project planning (optional)

This project has enough data and evaluation risk that its definitions should be settled before implementation.

## Recommended starting environment

Use Fedora in WSL as the provisional default because the project is likely to be a data pipeline, model-training workflow, and command-line or service application. This is an architectural starting point, not a verified requirement. Change it if a chosen data source, application integration, or deployment target requires Windows.

Keep the repository under:

```text
~/src/ncaam-team-total-projection
```

Start with the `General · WSL` VS Code profile. Choose and install the Python or other data stack only after the charter decisions below are made.

### If Python is selected

`uv` is a practical default for a new Python application because it manages Python
versions, project environments, dependencies, and a committed `uv.lock`. This is a
recommendation, not a settled NCAAM requirement. If the project chooses it, use the
current official instructions at <https://docs.astral.sh/uv/>.

The current Linux installer and project initialization sequence is:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
cd ~/src/ncaam-team-total-projection
uv init --app .
uv lock
```

Review the generated `pyproject.toml`, `.python-version`, `.gitignore`, package layout,
and README before adding dependencies. Change the Python version policy deliberately;
do not accept the generator's current default without checking deployment and library
compatibility. Commit `uv.lock` and manage it through `uv`, not by editing it manually.

## Define the prediction contract

Write down the answer to each item:

- **Unit:** one team in one game.
- **Target:** the exact statistic being projected, including overtime treatment.
- **Forecast time:** the timestamp at which inputs stop and the forecast becomes immutable.
- **Output:** point estimate, interval or distribution, confidence, and machine-readable reasoning fields.
- **Identity:** stable IDs for team, opponent, season, game, venue, and source.
- **Revision policy:** whether late injuries, lineup news, market movement, or schedule changes create a new forecast version.
- **Cancellation policy:** handling for postponed, cancelled, or abandoned games.

Do not use the phrase “team total” as if it defines all of these choices.

## Establish data rights and provenance

For every source, record:

- Provider and source URL or contract.
- Collection method.
- Fields used.
- Time observed, not only event time.
- Update and correction behavior.
- Storage and redistribution rights.
- Rate limits and authentication method.
- Raw-data checksum or immutable source version when possible.

Do not scrape or redistribute a source until its terms and permitted use are confirmed. Keep licensed raw data outside Git.

## Prevent future-information leakage

The system must reproduce what was knowable at forecast time. At minimum:

- Split evaluation by time, not random rows alone.
- Timestamp injuries, lineups, rankings, market data, and source corrections.
- Fit scalers, encoders, imputers, and feature selection only on the training period.
- Prevent the final score and postgame statistics from entering pregames features.
- Version team-name and conference mappings by season.
- Test the feature builder against an explicit as-of timestamp.

A model with leakage can look excellent while being useless. Leakage tests belong in the required gate.

## Separate projection from explanation

Treat these as different outputs:

1. The numerical projection and uncertainty estimate.
2. A structured record of the inputs and model contributions used.
3. A human-readable explanation derived only from that structured record.

The explanation must not invent injuries, trends, matchup facts, or causal claims. Every factual statement should trace to a stored input with a timestamp and source.

## Evaluation plan

Choose metrics before comparing models. Evaluate against simple baselines such as historical team average and a recency-weighted estimate before claiming improvement.

The evaluation should cover:

- Error by season and chronological holdout period.
- Home, away, and neutral-site games.
- Data availability and missing-input cases.
- Calibration of prediction intervals or distributions.
- Stability across teams and conferences.
- Performance before and after major rule or schedule changes.
- Reproducibility from a recorded dataset version and configuration.

If market totals are later used as a comparison, keep them timestamped and separate from the core target. Do not accidentally train on a value observed after the forecast cutoff.

## Safe first milestone

Build an end-to-end path using a tiny synthetic fixture:

1. Define the game and team schemas.
2. Validate a small input file.
3. Produce a baseline projection.
4. Emit structured reasoning linked to input fields.
5. Score the result against a fixture outcome.
6. Reproduce the run from one command.
7. Run formatting, linting, unit tests, schema tests, and leakage tests through the gate.

Do not begin with automated betting, account access, payment flows, or production wagering decisions. Those would add separate legal, financial, security, and operational requirements that this foundation does not establish.

## Suggested repository shape after the stack is chosen

```text
ncaam-team-total-projection/
├── README.md
├── PROJECT-CHARTER.md
├── AGENTS.md
├── CLAUDE.md
├── pyproject.toml or equivalent manifest
├── dependency lockfile
├── configs/
├── docs/
│   ├── DATA-SOURCES.md
│   ├── PREDICTION-CONTRACT.md
│   └── EVALUATION.md
├── src/
│   ├── ingest/
│   ├── schemas/
│   ├── features/
│   ├── models/
│   ├── evaluation/
│   └── explanation/
├── tests/
│   ├── fixtures/
│   ├── test_schemas.*
│   ├── test_as_of_time.*
│   └── test_leakage.*
└── scripts/
    └── check.sh
```

Adapt this shape to the selected language. Do not create empty modules only to match the diagram.

---
