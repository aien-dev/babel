# Dependencies

Babel is written in Omega (`src/*.om`). This file records every outside program in its build or run path. Each entry gives the version observed on the reference host (aarch64 Linux, Ubuntu 24.04, 2026-10-26), what babel uses it for, and its Omega replacement. Verification oracles are kept on purpose: they check babel's claims, and a replacement must not remove them.

## Build path

| Dependency | Version / pin | Purpose | Omega replacement |
|---|---|---|---|
| omc (OM-2 seed compiler) | aien-dev/omega-mv `0b77e6ea2:seed/out/omc`, sha256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` | Compiles babel | It is Omega's own compiler. Moves with the omega-mv reseeds. |
| sha256.om | aien-dev/omega-mv `4d41457466c42ccb52f405915fd95da469a439e3:src/source-aware/vendor/sha256.om`, sha256 `12d492b5f99b47b1e525067e1660c7cedbf6b414032cfc8b7e174919a28c052c`, **AGPL-3.0-or-later** | SHA-256 of input files and Omega units | Already Omega. The open question is licence: the built binary is a combined work (see README). |
| git, sha256sum, sh | Ubuntu 24.04 | `build.sh` fetches the pins and checks the compiler digest | Coordination only, not part of babel |

## Run path (programs babel spawns)

| Dependency | Version observed | Purpose | Omega replacement |
|---|---|---|---|
| omega-mv adapters `c-import`, `lower`, `<lang>-export`, `retarget` | `universal/624-g1-integration` `2d4c640702c82b8deb8a296407aadf660dac7fc7`; native omc sha256 `734f0a39…6b61` (babel refuses any other) | C → Omega import, lowering, Omega → target export | The computation and hashing already run in native Omega. The entry points are Python dispatch scripts (`#!/usr/bin/env python3`, "transparent host dispatch") that the #624 lanes own. Replacing them is adapter work, not babel work. |
| python3 | 3.12.3 | Runs the adapter dispatchers; the python target's interpreter | Dispatchers: native Omega entry points in omega-mv (#624). Target: none; Python output needs Python. |
| /usr/bin/env | coreutils 9.4 | Gives each child an explicit environment (`execprog` passes an empty one) | Omega `execprog` with an environment argument (PROPOSED compiler extension) |
| cc (gcc) | 13.3.0 | Builds the original C as the differential **oracle**; the c target's compiler | Oracle: keep, an independent oracle by design. c target: none needed to produce C. |
| cargo, rustc | 1.98.1 | Builds and tests the rust target | None: target toolchain |
| g++ | 13.3.0 | Builds the cpp target | None: target toolchain |
| zig | 0.17.0 (`ZIG=`) | Builds the zig target | None: target toolchain |
| go | 1.27.3 (`GO=`, `GOTOOLCHAIN=local`) | Builds the go target | None: target toolchain |

Toolchain versions are recorded per run in `report.json` (`toolchains`). If a toolchain is missing, the affected units get NOT_RUN, never TRANSLATED.

## Test path

`tests/run.sh` uses sh, cmp, awk, grep, sed, wc, mktemp and `python3 -m json.tool`. They are independent checkers of babel's output, kept as oracles.
