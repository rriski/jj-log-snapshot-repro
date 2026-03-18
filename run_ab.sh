#!/usr/bin/env bash
set -euo pipefail

jj_bin="${JJ_BIN:-jj}"
depth="${1:-200}"
files="${2:-100}"
root="${3:-/tmp/jj-repro-ab}"
target_repo_only="${4:-0}"

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"

base_repo="$root/base"
exp_repo="$root/exp"

if [[ "$target_repo_only" == "1" ]]; then
  echo "[ab] benchmarking only existing repo: $root" >&2
  base_repo="$root"
  exp_repo="$root"
else
  echo "[ab] generating baseline repo: $base_repo" >&2
  "$script_dir/gen_conflict_chain.sh" "$base_repo" "$depth" "$files" 1 >/dev/null
  echo "[ab] generating experimental repo: $exp_repo" >&2
  "$script_dir/gen_conflict_chain.sh" "$exp_repo" "$depth" "$files" 1 >/dev/null
fi

"$jj_bin" config set --repository "$base_repo" --repo merge.same-change keep >/dev/null
"$jj_bin" config set --repository "$exp_repo" --repo merge.same-change keep >/dev/null

measure_ms() {
  local repo="$1"
  local cmd="$2"
  uv run --python 3.12 python - <<PY
import subprocess,time
t0=time.perf_counter()
subprocess.run(["bash","-lc", ${cmd@Q}], cwd=${repo@Q}, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(int((time.perf_counter()-t0)*1000))
PY
}

printf 'baseline\n' > "$base_repo/trigger.txt"
base_slow_ms=$(measure_ms "$base_repo" "$jj_bin log")

printf 'experimental\n' > "$exp_repo/trigger.txt"
exp_slow_ms=$(measure_ms "$exp_repo" "JJ_EXPERIMENTAL_REBASE_SKIP_FINAL_RESOLVE=1 $jj_bin log")

printf 'fast\n' > "$base_repo/trigger.txt"
fast_ms=$(measure_ms "$base_repo" "$jj_bin log --ignore-working-copy")

base_ratio=$(awk -v s="$base_slow_ms" -v f="$fast_ms" 'BEGIN { if (f==0) print "inf"; else printf "%.2f", s/f }')
exp_ratio=$(awk -v s="$exp_slow_ms" -v f="$fast_ms" 'BEGIN { if (f==0) print "inf"; else printf "%.2f", s/f }')
speedup=$(awk -v b="$base_slow_ms" -v e="$exp_slow_ms" 'BEGIN { if (b==0) print "0.00"; else printf "%.2f", (b-e)*100/b }')

echo "depth=$depth files=$files"
echo "baseline_repo=$base_repo"
echo "experimental_repo=$exp_repo"
echo "baseline_jj_log_ms=$base_slow_ms"
echo "experimental_jj_log_ms=$exp_slow_ms"
echo "ignore_working_copy_ms=$fast_ms"
echo "baseline_ratio=${base_ratio}x"
echo "experimental_ratio=${exp_ratio}x"
echo "speedup_vs_baseline_pct=${speedup}%"
