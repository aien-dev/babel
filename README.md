# babel

`babel` translates code through **Omega**, the explicit computational language of [AienOS](https://www.aienos.com). You point it at a folder. It writes the translation next to the folder: the input, the Omega form and the target language. It also writes a report that accounts for every function and every declaration in the input.

```
$ babel examples/sample --to rust
```

```
examples/sample.babel/
  input/          byte copy of every input file (sha256 recorded while copying)
  omega/          one Omega unit per translated function, plus manifest.json
  rust/           the target project (Cargo crate, differential test, driver)
  diff/<name>/    vectors.txt, oracle.c, driver.om, c-original.out, omega.out, target.out
  REPORT.md       per-file, per-item verdicts with reasons and line ranges
  report.json     the same, schema babel.report.v1
```

With no `--to` and a terminal on stdin, babel asks for the target language. `--json` prints `report.json` on stdout instead of the summary table. `--complete` makes the exit status follow the completion record (see [Completion](#completion)).

**Status: pre-alpha.** Only one narrow profile is implemented, and anything outside it is refused by name. The [ROADMAP](ROADMAP.md) is PROPOSED work, not a feature list.

## What is supported today

Profile **S1 `c17-uint64-pure-v1`**: C17 functions whose parameters and result are `uint64_t`. Up to 6 parameters; the body is a pure arithmetic expression. Arithmetic wraps modulo 2^64, as in C. These are the adapters of [aien-dev/omega-mv](https://github.com/aien-dev/omega-mv) #624, pinned at `universal/624-g1-integration` `2d4c6407`.

| From \ to | rust | c | python | cpp | zig | go |
|---|---|---|---|---|---|---|
| C17, S1 functions | EXERCISED | EXERCISED | EXERCISED | EXERCISED | EXERCISED | EXERCISED |
| C: anything else (globals, structs, pointers, branches, calls, libc, preprocessor) | refused | refused | refused | refused | refused | refused |
| Python, Rust, C++, Zig, Go input | MISSING_IMPLEMENTATION | ← | ← | ← | ← | ← |

EXERCISED means that `tests/run.sh` ran on `examples/sample` on an arm64 Linux host. Each of the six targets gave 5 TRANSLATED, 7 UNSUPPORTED, 5 MISSING_IMPLEMENTATION, 0 FAIL and 2 ABSORBED. CI repeats this on a GitHub `ubuntu-24.04-arm` runner. That is host evidence: it is not hardware qualification, and it is not a release.

The omega-mv `<lang>-import` adapters exist for Rust, Python, C++, Zig and Go, one function per unit. Babel has no splitter for those languages, so their files are reported MISSING_IMPLEMENTATION with that reason. Babel does not guess.

## Verdicts

| Verdict | Meaning |
|---|---|
| TRANSLATED | The adapter exited 0, the pinned omc accepted the Omega unit, and **the original C, the Omega unit and the target output are byte-identical on every vector**. |
| UNSUPPORTED(rc) | An adapter refused the function with a profile exit code. The codes are 64 name, 65 syntax, 66 type, 67 limit, 68 arithmetic, 69 construct, 70 unknown identifier, 71 signature and 72 preprocessor. |
| MISSING_IMPLEMENTATION | Nothing in the pipeline handles this item: C declarations, preprocessor lines, other languages. The reason names the item. |
| FAIL | A stage ran and disagreed: an output differed on a vector, a build failed, or the oracle failed. Babel exits 1. |
| NOT_RUN | A required toolchain is absent, so the check did not happen. It does not count as a pass. A `ZIG=` or `GO=` path that is not executable counts as absent. |
| ABSORBED | `#include <stdint.h>`: the S1 profile header, which babel supplies to every unit. |
| SKIPPED | Completion record only: an entry the walk did not enter (hidden entry, symbolic link, other non-regular file, `*.babel` folder, unreadable directory). |

The vectors are the boundary values {0, 1, 2, 2^32−1, 2^32, 2^63−1, 2^63, 2^64−2, 2^64−1}. Functions of arity ≤ 3 get the full cross product; higher arities get 81 rows. Every function also gets 64 splitmix64 vectors from seed 20261026. The original C function is compiled verbatim by `cc` as the oracle. Babel never stores or replays source: every target file is adapter output.

## Completion

Every run computes a completion record, policy `complete-v1`, and writes it to `report.json` (`"completion"`), to a "Completion" section of REPORT.md and to one summary line. Its denominator counts:

- every walked file (a file in a language babel does not recognise, such as `README.txt`, is open as MISSING_IMPLEMENTATION);
- every split item (TRANSLATED, ABSORBED, UNSUPPORTED, MISSING_IMPLEMENTATION, FAIL, NOT_RUN);
- every SKIPPED entry, each listed by path;
- every required check: the three differential legs (original C, Omega, target) of each unit that reached the differential, the generated target test for rust and python, and each toolchain the target needs (`cc` for the oracle plus the target's own).

The state is the first that applies:

| State | Condition |
|---|---|
| FAILED | Any FAIL item or check, including a failed generated test. |
| BLOCKED | No FAIL, but a required check is NOT_RUN or a toolchain is missing. |
| PARTIAL | No FAIL and no NOT_RUN, but UNSUPPORTED, MISSING_IMPLEMENTATION or SKIPPED items remain. |
| COMPLETE | Every item TRANSLATED or ABSORBED, nothing skipped, every required check ran and passed. |

```
"completion": {"policy": "complete-v1", "enforced": false, "state": "PARTIAL", "denominator": 39, "covered": 26,
  "open": [{"kind": "unit", "item": "src/mix.c:15-17", "name": "zero", "verdict": "UNSUPPORTED(68)", "reason": "..."}, ...]}
```

`kind` is `file`, `unit`, `skipped`, `check` or `toolchain`; `item` is `path:line[-line]` for units and their legs, a path for files and skipped entries, and a tool name for toolchains. `enforced` is true under `--complete`. `examples/sample` is PARTIAL (26 of 39); `examples/complete` (three S1 functions and the stdint include) is COMPLETE.

`tests/run.sh` checks all of this independently of babel:

- `cmp` on the three outputs;
- line counts against the vector count;
- `python3 -m json.tool` on both JSON outputs;
- a **negative control**: a `cc` wrapper changes `fold`'s original C (`- k` to `+ k`) only when compiling the oracle. Babel must then report FAIL ("differs from the original C on 127 of 145 vectors") and exit 1;
- the completion gate: `examples/sample --complete` is PARTIAL and exits 3; `examples/complete --complete` is COMPLETE and exits 0 (c and rust); the same input plus one hidden file, or plus one symbolic link, is PARTIAL and exits 3 with that entry as the only open item; the `cc` wrapper under `--complete` is FAILED and exits 1; `ZIG=/nonexistent --to zig --complete` is BLOCKED and exits 4.

## Why Omega is the middle

Translating between N languages directly needs N×M translators. Going through one intermediate language needs N front-ends and M back-ends. This is the old UNCOL idea (1958). UNCOL failed because its intermediate form was pseudo-assembly: it either lost the source semantics or bloated into the union of every machine.

Babel uses Omega as the middle on a different basis:

- **Omega carries semantics, not instructions.** An imported function becomes a typed Omega unit with an explicit arithmetic contract: u64 wrapping. The pinned compiler checks that unit, and it is run as one of the three differential legs.
- **Every target has a realization contract.** A back-end may emit only constructs whose meaning matches the Omega unit. Anything without a contract is refused. Nothing is approximated.
- **Effects are explicit.** S1 is pure, so I/O, globals and pointers are refused at import rather than translated loosely. Wider profiles must name their effects before a target can realize them.
- **Every claim is checked.** No unit is called TRANSLATED until all three legs agree byte for byte.

## Build and run

Requirements, recorded in [DEPENDENCIES.md](DEPENDENCIES.md):

- an aarch64 Linux host;
- a clone of [aien-dev/omega-mv](https://github.com/aien-dev/omega-mv) with the adapters built;
- the target toolchains.

```
git clone https://github.com/aien-dev/omega-mv && git clone https://github.com/aien-dev/omega-bridge
(cd omega-mv && git checkout 2d4c640702c82b8deb8a296407aadf660dac7fc7 && \
 make -f mk/translation.mk test-translation-g3 SA_SEED_REPO=$PWD/../omega-bridge OMEGA_BRIDGE_REPO=$PWD/../omega-bridge)
OMEGA_MV=$PWD/omega-mv ./build.sh            # build/babel, compiled by the pinned omc
BABEL_ADAPTERS=$PWD/omega-mv build/babel examples/sample --to go
BABEL_ADAPTERS=$PWD/omega-mv tests/run.sh    # ZIG=/GO= if not on PATH
```

Babel refuses to run unless the adapters' native omc has sha256 `734f0a39…6b61`. Re-running babel replaces `input/`, `omega/`, `diff/` and the folder for the chosen language. Folders for other languages are kept. Hidden entries, symlinks and `*.babel` folders are not walked; each is counted and listed as SKIPPED in the completion record.

Exit codes:

| Code | Without `--complete` | With `--complete` |
|---|---|---|
| 0 | No FAIL | COMPLETE |
| 1 | At least one FAIL, or the generated test failed | FAILED |
| 2 | Usage or environment error | same |
| 3 | not used | PARTIAL |
| 4 | not used | BLOCKED |
| 64 | No `--to` and no terminal | same |

## Implementation

Babel itself is written in Omega (`src/*.om`, 5,923 lines). It walks files, hashes them, splits C top-level items, spawns the adapters and toolchains, generates the projects and drivers, compares outputs and writes the reports.

The only shell is in `build.sh` and `tests/run.sh`, which coordinate the build and run independent checks. Host programs babel launches are listed in [DEPENDENCIES.md](DEPENDENCIES.md), each with its Omega replacement.

## Licence

Apache-2.0 with the LLVM exception ([LICENSE](LICENSE), [NOTICE](NOTICE)). `build.sh` compiles babel's source together with two Apache-2.0 files from aien-dev/omega-mv at `0b77e6ea2`: the OM-2 compiler `seed/out/omc` and the SHA-256 unit `om/sha256/sha256-om2.om`. It checks the sha256 digest of both files.

## Human-Directed Agentic Engineering

Development follows Human-Directed Agentic Engineering (HDAE): humans define goals,
architecture, constraints, acceptance criteria, and stopping points; agents implement,
execute checks, diagnose failures, and revise within those boundaries. Human review
retains responsibility for claims, acceptance, and release decisions.

For the documented method and a systems-software case study, see Gregory M. Kurtzer,
[*Ginux: Building an Independent Kernel That Runs Linux Userspace through
Human-Directed Agentic Engineering* (2026)](https://doi.org/10.5281/zenodo.23682548).
This citation describes the development method, not runtime autonomy or an endorsement.
