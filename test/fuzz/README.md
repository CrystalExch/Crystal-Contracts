# Crystal Stateful Fuzzing

The fuzz runners live under tool-named test folders:

- `test/echidna/run-echidna.ps1`
- `test/medusa/run-medusa.ps1`

Shared setup, stop, and reporting helpers live in `test/fuzz/`.

## One-time setup

```powershell
npm run fuzz:tools
```

This starts Docker Desktop if needed, pulls:

- `ghcr.io/crytic/echidna/echidna:latest`
- `ghcr.io/crytic/medusa:latest`

Then it builds `crystal-medusa-foundry:latest`, a local Medusa image with Foundry copied in for `crytic-compile --foundry-compile-all`, and verifies Echidna, Medusa, `crytic-compile`, and Foundry inside the containers.

## Overnight runs

Medusa is usually the better first overnight campaign:

```powershell
npm run fuzz:medusa:bg
```

Echidna:

```powershell
npm run fuzz:echidna:bg
```

Logs are written under `logs/`. Corpora are written under `corpus/echidna` and `corpus/medusa`.

## Stop running fuzzers

```powershell
npm run fuzz:stop
```

This stops containers named `crystal-medusa-*` and `crystal-echidna-*`.

## Generate triage markdown

```powershell
npm run fuzz:report
```

This scans logs, Foundry failure caches, and fuzzing corpora, then writes `FUZZ_FINDINGS.md`.

## Manual foreground runs

```powershell
npm run fuzz:medusa
npm run fuzz:echidna
```

Foreground runs stream output to the terminal and also save a timestamped log.
