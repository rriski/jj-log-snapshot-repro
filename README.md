# jj log slow on conflicted descendant chains

Minimal reproduction for a `jj log` slowdown when the working-copy commit has a
long chain of conflicted descendants.

## What this repo contains

- `gen_conflict_chain.sh`: generates a deterministic synthetic jj repo
- `run_repro.sh`: runs a minimal benchmark (`jj log` vs `--ignore-working-copy`)

Generated repo shape:

- conflicted merge root (`conflict-root`)
- linear chain of conflicted descendants
- configurable number of conflicted files

## Requirements

- `jj`
- `bash`
- `uv` (used by `run_repro.sh` for timing)

Optional:

- `samply`

## Quick start

```bash
./run_repro.sh /tmp/jj-repro 200 100
```

This will print:

- `jj_log_ms`
- `jj_log_ignore_wc_ms`
- ratio

Expected: `jj log` is significantly slower than `jj log --ignore-working-copy`.

## Side-by-side baseline vs experimental

Use a custom jj binary and compare baseline to the experimental env flag:

```bash
JJ_BIN=/home/riski/dev/3rdparty/jj/target/release/jj \
  ./run_ab.sh 200 100 /tmp/jj-repro-ab
```

This script sets `merge.same-change=keep` in both generated repos and runs:

- baseline: `jj log`
- experimental: `JJ_EXPERIMENTAL_REBASE_SKIP_FINAL_RESOLVE=1 jj log`

## Manual repro

```bash
./gen_conflict_chain.sh /tmp/jj-repro 200 100 1
cd /tmp/jj-repro
printf 'trigger\n' > trigger.txt
time jj log
printf 'trigger\n' > trigger.txt
time jj log --ignore-working-copy
```

## Trace capture

```bash
JJ_TRACE=/tmp/jj-repro-slow.json jj log
JJ_TRACE=/tmp/jj-repro-fast.json jj log --ignore-working-copy
```

Optional CPU profile:

```bash
samply record --save-only -o /tmp/jj-repro-slow-samply.json -- timeout -s INT -k 3s 120s jj log
```
