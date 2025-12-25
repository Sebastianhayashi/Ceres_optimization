#!/usr/bin/env bash
set -euo pipefail
trap 'echo "FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR

# gcc14（关键：source enable 前临时关 -u，避免 enable 脚本触发 unbound variable 导致 shell 退出）
set +u
source /opt/openEuler/gcc-toolset-14/enable
set -u

DEPS_BASE="$HOME/cartodeps/base"

# 自动找 pose_graph_2d（优先约定路径）
BIN_BASE="$HOME/ceres-solver/build-base/bin/pose_graph_2d"
if [[ ! -x "$BIN_BASE" ]]; then
  BIN_BASE="$(find "$HOME/ceres-solver" -maxdepth 4 -type f -name pose_graph_2d -perm -u+x | head -n 1 || true)"
fi
[[ -x "${BIN_BASE:-}" ]] || { echo "ERROR: pose_graph_2d not found under ~/ceres-solver" >&2; exit 1; }

# 自动找 g2o 数据目录（按常见落点顺序尝试）
DATA_DIR=""
for d in \
  "$HOME/planar_pgo_datasets/datasets" \
  "$HOME/datasets/g2o" \
  "$HOME/datasets/g2o/planar_pgo_datasets/datasets" \
  "$HOME/planar_pgo_datasets" \
  "$HOME/datasets"
do
  if compgen -G "$d/*.g2o" >/dev/null 2>&1; then DATA_DIR="$d"; break; fi
done
[[ -n "$DATA_DIR" ]] || { echo "ERROR: no .g2o found under ~/datasets or ~/planar_pgo_datasets" >&2; exit 1; }

OUT_ROOT="$HOME/results/ceres_pose_graph_2d/base_sweep_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_ROOT"
SUMMARY="$OUT_ROOT/summary.tsv"
printf "dataset\tbytes\texit_code\twall\tmax_rss_kb\tcase_dir\n" > "$SUMMARY"

# 运行时绑定 base 动态库
export LD_LIBRARY_PATH="$DEPS_BASE/lib64:$DEPS_BASE/lib:${LD_LIBRARY_PATH:-}"

echo "BIN_BASE=$BIN_BASE"
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
  ( /usr/bin/time -v "$BIN_BASE" --input="$f" ) 2>&1 | tee run.log || rc=$?

  bytes="$(stat -c %s "$f" 2>/dev/null || wc -c <"$f" || echo NA)"
  wall="$(grep -m1 'Elapsed (wall clock) time' run.log | sed 's/^.*: //' || true)"
  maxrss="$(grep -m1 'Maximum resident set size' run.log | sed 's/^.*: //' || true)"
  wall="${wall:-NA}"
  maxrss="${maxrss:-NA}"

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$b" "$bytes" "$rc" "$wall" "$maxrss" "$case_dir" >> "$SUMMARY"
  popd >/dev/null
done

echo "DONE. SUMMARY=$SUMMARY"
