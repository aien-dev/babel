# Roadmap — PROPOSED

Nothing in this file is implemented unless the README matrix says so. Each step lands only with:

- the verdicts from `tests/run.sh`;
- a negative control that makes it fail;
- an updated README matrix.

| Step | What | Depends on |
|---|---|---|
| R1 | Profile S2: wider C integer/control-flow profile, imported through the omega-mv #624 S2 adapters once their lane publishes a TESTED revision | aien-dev/omega-mv #624 / #622 |
| R2 | Front-ends for Rust, Python, C++, Zig and Go input. The omega-mv `<lang>-import` adapters exist for one function per unit; babel needs a splitter per language. | #626, #627, #739, #740, #741 |
| R3 | Declarations: C globals and structs as explicit Omega state, with effects named | #628 target contracts |
| R4 | Independent validation per target (a second checker besides the three-leg differential) | #623 |
| R5 | Native Omega adapter entry points replacing the Python dispatchers | #624 lanes |
| R6 | An environment argument for Omega `execprog`, removing `/usr/bin/env` | omega-mv compiler (batch process) |
| R7 | Apache-licensed Omega SHA-256, or another licence decision for `sha256.om` | Drake |
| R8 | Richer UI on top of `report.json` (the CLI stays the reference) | — |
