#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gen_conflict_chain.sh [REPO_PATH] [CHAIN_LENGTH] [CONFLICT_FILES] [EDIT_TO_ROOT]

Creates a deterministic jj repository with:
  - base commit tracking conflict files + trigger.txt
  - two divergent commits (sideA/sideB) changing the same line
  - a conflicted merge commit bookmarked as conflict-root
  - a linear chain of CHAIN_LENGTH conflicted descendants
  - optional `jj edit conflict-root` so descendants are on top of `@`

Defaults:
  REPO_PATH=/tmp/jj-perf-lab/repos/repro
  CHAIN_LENGTH=100
  CONFLICT_FILES=1
  EDIT_TO_ROOT=1
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

repo_path="${1:-/tmp/jj-perf-lab/repos/repro}"
chain_len="${2:-100}"
conflict_files="${3:-1}"
edit_to_root="${4:-1}"

if ! [[ "$chain_len" =~ ^[0-9]+$ ]]; then
  echo "CHAIN_LENGTH must be a non-negative integer" >&2
  exit 2
fi

if ! [[ "$conflict_files" =~ ^[0-9]+$ ]] || (( conflict_files < 1 )); then
  echo "CONFLICT_FILES must be a positive integer" >&2
  exit 2
fi

if ! [[ "$edit_to_root" =~ ^[01]$ ]]; then
  echo "EDIT_TO_ROOT must be 0 or 1" >&2
  exit 2
fi

mkdir -p "$(dirname "$repo_path")"
rm -rf "$repo_path"

echo "[repro] init repo: $repo_path" >&2
jj git init --colocate "$repo_path" >/dev/null

cd "$repo_path"

for i in $(seq 1 "$conflict_files"); do
  file=$(printf 'file-%03d.txt' "$i")
  printf 'base-%03d\n' "$i" > "$file"
  jj --quiet file track "$file"
done
printf 'trigger-base\n' > trigger.txt
jj --quiet file track trigger.txt
jj --quiet commit -m base
jj --quiet bookmark create base -r @-

jj --quiet new base
for i in $(seq 1 "$conflict_files"); do
  file=$(printf 'file-%03d.txt' "$i")
  printf 'A-%03d\n' "$i" > "$file"
done
jj --quiet commit -m side-A
jj --quiet bookmark create sideA -r @-

jj --quiet new base
for i in $(seq 1 "$conflict_files"); do
  file=$(printf 'file-%03d.txt' "$i")
  printf 'B-%03d\n' "$i" > "$file"
done
jj --quiet commit -m side-B
jj --quiet bookmark create sideB -r @-

jj --quiet new sideA sideB
jj --quiet describe -m conflict-root
jj --quiet bookmark create conflict-root -r @

echo "[repro] build conflicted chain: $chain_len commits" >&2

if (( chain_len > 0 )); then
  for i in $(seq 1 "$chain_len"); do
    jj --quiet new @
    jj --quiet describe -m "chain-$i"
    if (( i % 25 == 0 || i == chain_len )); then
      echo "[repro] chain progress: $i/$chain_len" >&2
    fi
  done
fi

if (( edit_to_root == 1 )); then
  echo "[repro] move working copy to conflict-root" >&2
  jj edit conflict-root >/dev/null
fi

# Ensure working copy will trigger snapshot rewrite in timing scripts.
printf 'trigger-dirty-initial\n' > trigger.txt

total_descendants_root=$(jj --ignore-working-copy log -r 'descendants(conflict-root)' --count)
conflicted_descendants_root=$(jj --ignore-working-copy log -r 'descendants(conflict-root) & conflicts()' --count)
total_descendants_at=$(jj --ignore-working-copy log -r 'descendants(@)' --count)
conflicted_descendants_at=$(jj --ignore-working-copy log -r 'descendants(@) & conflicts()' --count)

echo "repo=$repo_path"
echo "chain_length=$chain_len"
echo "conflict_files=$conflict_files"
echo "edit_to_root=$edit_to_root"
echo "descendants(conflict-root)=$total_descendants_root"
echo "conflicted_descendants(conflict-root)=$conflicted_descendants_root"
echo "descendants(@)=$total_descendants_at"
echo "conflicted_descendants(@)=$conflicted_descendants_at"

jj --ignore-working-copy log --no-graph -n 8
