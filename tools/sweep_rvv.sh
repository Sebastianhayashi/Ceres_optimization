#!/usr/bin/env bash
set -euo pipefail
trap 'echo "FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR

# gcc14（同样：source enable 前临时关 -u）
set +u
source /opt/openEuler/gcc-toolset-14/enable
set -u

DEPS_RVV="$HOME/cartodeps/rvv"
BIN_RVV="$HOME/ceres-solver/build-rvv/bin/pose_graph_2d"
DATA_DIR="$HOME/planar_pgo_datasets/datasets"

OUT_ROOT="$HOME/results/ceres_pose_graph_2d/rvv_sweep_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_ROOT"
SUMMARY="$OUT_ROOT/summary.tsv"
printf "dataset\tbytes\texit_code\twall\tmax_rss_kb\tcase_dir\n" > "$SUMMARY"

export LD_LIBRARY_PATH="$DEPS_RVV/lib64:$DEPS_RVV/lib:${LD_LIBRARY_PATH:-}"

test -x "$BIN_RVV"
test -d "$DATA_DIR"

echo "BIN_RVV=$BIN_RVV"
echo "DATA_DIR=$DATA_DIR"
echo "OUT_ROOT=$OUT_ROOT"

shopt -s nullglob
for f in "$DATA_DIR"/*.g2o; do
  b="$(basename "$f")"
  stem="${b%.g2o}"
  case_dir="$OUT_ROOT/$stem"
  mkdir -p "$case_dir"
  pushd "$case_dir" >/dev/null

  rc=0
  ( /usr/bin/time -v "$BIN_RVV" --input="$f" ) 2>&1 | tee run.log || rc=$?

  bytes="$(stat -c %s "$f" 2>/dev/null || wc -c <"$f" || echo NA)"
  wall="$(grep -m1 'Elapsed (wall clock) time' run.log | sed 's/^.*: //' || true)"
  maxrss="$(grep -m1 'Maximum resident set size' run.log | sed 's/^.*: //' || true)"
  wall="${wall:-NA}"
  maxrss="${maxrss:-NA}"

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$b" "$bytes" "$rc" "$wall" "$maxrss" "$case_dir" >> "$SUMMARY"
  popd >/dev/null
done

echo "DONE. SUMMARY=$SUMMARY"
