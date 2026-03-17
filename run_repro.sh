#!/usr/bin/env bash
set -euo pipefail

repo="${1:-/tmp/jj-repro}"
depth="${2:-200}"
files="${3:-100}"
jj_bin="${JJ_BIN:-jj}"

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
"$script_dir/gen_conflict_chain.sh" "$repo" "$depth" "$files" 1 >/dev/null

cd "$repo"
printf 'trigger-slow\n' > trigger.txt

slow_ms=$(uv run --python 3.12 python - <<PY
import subprocess, time
t0 = time.perf_counter()
subprocess.run(["bash","-lc", "${jj_bin} log >/dev/null"], check=True)
print(int((time.perf_counter() - t0) * 1000))
PY
)

printf 'trigger-fast\n' > trigger.txt
fast_ms=$(uv run --python 3.12 python - <<PY
import subprocess, time
t0 = time.perf_counter()
subprocess.run(["bash","-lc", "${jj_bin} log --ignore-working-copy >/dev/null"], check=True)
print(int((time.perf_counter() - t0) * 1000))
PY
)

ratio=$(awk -v s="$slow_ms" -v f="$fast_ms" 'BEGIN { if (f==0) print "inf"; else printf "%.2f", s/f }')

echo "repo=$repo depth=$depth files=$files"
echo "jj_log_ms=$slow_ms"
echo "jj_log_ignore_wc_ms=$fast_ms"
echo "ratio=${ratio}x"
