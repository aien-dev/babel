# Security

Report vulnerabilities privately through GitHub security advisories on this repository (Security → Report a vulnerability). Do not report them in public issues.

## Threat model

Babel reads untrusted source trees and runs toolchains on code derived from them:

- the original C, compiled and executed as the differential oracle;
- the generated target, built and executed.

**Running babel on a tree executes code from that tree.** Run it only on code you would build yourself, or inside a sandbox or VM.

What babel itself does:

- It writes only under `<input>.babel/`. It does not follow symlinks or walk hidden entries.
- It starts child processes with an explicit environment (through `/usr/bin/env`). It uses no shell, so input text is never parsed as shell.
- It runs the go toolchain with `GOPROXY=off` and `GOTOOLCHAIN=local`, and cargo with `CARGO_NET_OFFLINE=true`.
- It refuses to run unless the adapters' native omc has the pinned sha256.
