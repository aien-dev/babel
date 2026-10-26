# Instructions for agents

- **Product:** a translator that goes through Omega. Honesty is the product. A unit is TRANSLATED only when three legs agree byte for byte on every vector: the original C, the Omega unit and the target output. Never approximate, never replay stored source, never weaken `tests/run.sh` or its negative control.
- **Language:** babel is `.om` (`src/*.om`, compiled in file order by the pinned omc in `build.sh`). Shell is allowed only in `build.sh` and `tests/`. New host programs go in DEPENDENCIES.md with version, purpose and Omega replacement.
- **Adapters** belong to aien-dev/omega-mv (#624 lanes). Do not copy or fork them here. Change them there.
- **Compiler gotchas (omc 2c824805):**
  - A statement starting with an unknown name silently becomes an assignment; the lint in `tests/run.sh` catches this.
  - An empty `text X ""` passed as a view has a garbage length. It is fixed upstream as compile error 8, pending reseed; never use empty texts.
  - Limits: ≤ 6 parameter slots, a view counts as 2; names ≤ 8 characters; `ret` must be last in its block.
- **Workflow:** after the initial scaffold, changes land by pull request. Run `OMEGA_MV=… ./build.sh && BABEL_ADAPTERS=… tests/run.sh` before opening one, and quote its output.
- **Status words:** PROPOSED, IMPLEMENTED, EXERCISED, VERIFIED, QUALIFIED, MERGED, DEPLOYED. Host CI is not hardware qualification.
