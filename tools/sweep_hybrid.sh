#!/usr/bin/env bash
set -euo pipefail

# --------- user-configurable (env override) ----------
CERES_DIR="${CERES_DIR:-$HOME/ceres-solver}"

BASE_EXE="${BASE_EXE:-$CERES_DIR/build-base/bin/pose_graph_2d}"
RVV_EXE="${RVV_EXE:-$CERES_DIR/build-rvv/bin/pose_graph_2d}"

# 如果你想复用已有 hybrid，直接 export HYB_EXE=... 并设置 BUILD_HYBRID=0
BUILD_HYBRID="${BUILD_HYBRID:-1}"
HYB_EXE="${HYB_EXE:-}"

BUILD_DIR_RVV="${BUILD_DIR_RVV:-$CERES_DIR/build-rvv}"
COMPDB="${COMPDB:-$BUILD_DIR_RVV/compile_commands.json}"
BUILD_HYBRID_SCRIPT="${BUILD_HYBRID_SCRIPT:-$CERES_DIR/build_hybrid_pose_graph.sh}"

DATA_DIR="${DATA_DIR:-$HOME/planar_pgo_datasets/datasets}"
CASE1="${CASE1:-$DATA_DIR/city10000_1.g2o}"
CASE3="${CASE3:-$DATA_DIR/city10000_3.g2o}"

PIN="${PIN:-taskset -c 0}"
DO_PERF="${DO_PERF:-1}"
PERF_EVENT="${PERF_EVENT:-cpu-clock}"
PERF_CYCLES="${PERF_CYCLES:-1000000}"   # -c

EXTRA_FLAGS="${EXTRA_FLAGS:--fno-tree-vectorize -fno-tree-slp-vectorize}"
# ----------------------------------------------------

# toolchain (safe even if already sourced)
set +u; source /opt/openEuler/gcc-toolset-14/enable; set -u

ts="$(date +%Y%m%d_%H%M%S)"
OUT="$HOME/results/ceres_pose_graph_2d/repro_hybrid_$ts"
mkdir -p "$OUT"
echo "$OUT" > "$HOME/results/ceres_pose_graph_2d/repro_hybrid_latest_path.txt"

echo "BASE_EXE=$BASE_EXE"
echo "RVV_EXE=$RVV_EXE"
echo "CERES_DIR=$CERES_DIR"
echo "BUILD_DIR_RVV=$BUILD_DIR_RVV"
echo "CASE1=$CASE1"
echo "CASE3=$CASE3"
echo "PIN=$PIN"
echo "OUT=$OUT"
echo

test -x "$BASE_EXE"
test -x "$RVV_EXE"
test -f "$CASE1"
test -f "$CASE3"

maybe_build_hybrid() {
  if [[ "$BUILD_HYBRID" != "1" ]]; then
    if [[ -z "${HYB_EXE}" ]]; then
      echo "ERROR: BUILD_HYBRID=0 but HYB_EXE is empty" >&2
      exit 2
    fi
    return 0
  fi

  # ensure compdb exists (no source change)
  if [[ ! -f "$COMPDB" ]]; then
    echo "compile_commands.json not found, reconfigure build-rvv with EXPORT_COMPILE_COMMANDS=ON"
    cmake -S "$CERES_DIR" -B "$BUILD_DIR_RVV" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="$HOME/cartodeps/rvv" \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  fi
  test -f "$COMPDB"

  echo "== build hybrid TU: pose_graph_2d.cc with EXTRA_FLAGS: $EXTRA_FLAGS =="
  # build script prints "OK: HYBRID_EXE=..."
  local log="$OUT/build_hybrid.log"
  set +e
  ( COMPDB="$COMPDB" BUILD_DIR="$BUILD_DIR_RVV" SRC_BASENAME="pose_graph_2d.cc" EXTRA_FLAGS="$EXTRA_FLAGS" \
      bash "$BUILD_HYBRID_SCRIPT" ) |& tee "$log"
  local rc="${PIPESTATUS[0]}"
  set -e
  if [[ "$rc" != "0" ]]; then
    echo "ERROR: build_hybrid script failed, see $log" >&2
    exit 3
  fi

  HYB_EXE="$(grep -Eo '^OK: HYBRID_EXE=.*' "$log" | tail -n 1 | sed 's/^OK: HYBRID_EXE=//')"
  if [[ -z "$HYB_EXE" || ! -x "$HYB_EXE" ]]; then
    echo "ERROR: cannot parse HYB_EXE from $log, or file not executable" >&2
    exit 4
  fi

  echo "HYB_EXE=$HYB_EXE"
  echo
}

run_one() {
  local tag="$1"   # base/rvv/hyb
  local ds="$2"    # city10000_1 / city10000_3
  local exe="$3"
  local input="$4"

  echo "== run $tag $ds =="
  # warm-up
  $PIN "$exe" --input="$input" >/dev/null 2>&1 || true

  # solver log
  $PIN "$exe" --input="$input" >"$OUT/$tag.$ds.log" 2>"$OUT/$tag.$ds.stderr" || true
  echo "DONE $tag $ds (log: $OUT/$tag.$ds.log)"

  if [[ "$DO_PERF" == "1" ]]; then
    $PIN perf record -e "$PERF_EVENT" -c "$PERF_CYCLES" \
      -o "$OUT/$tag.$ds.data" -- "$exe" --input="$input" \
      >"$OUT/$tag.$ds.perf.stdout" 2>"$OUT/$tag.$ds.perf.stderr" || true

    perf report --stdio -i "$OUT/$tag.$ds.data" --no-children --percent-limit 1 \
      | head -n 200 > "$OUT/$tag.$ds.report.txt"
    echo "DONE $tag $ds (perf: $OUT/$tag.$ds.data)"
  fi
  echo
}

parse_timeblk () {
  awk '
    function first_float(line,   m) {
      if (match(line, /[0-9]+\.[0-9]+/, m)) return m[0]+0;
      return 0;
    }
    /^[[:space:]]*Time[[:space:]]*\(in[[:space:]]+seconds\)[[:space:]]*:/ { inblk=1; next }
    inblk && /Residual[[:space:]]+only[[:space:]]+evaluation/ { ro = first_float($0) }
    inblk && /Jacobian/ && /evaluation/ { jr = first_float($0) }
    inblk && /^[[:space:]]+Linear[[:space:]]+solver/ { ls = first_float($0) }
    inblk && /^[[:space:]]*Total[[:space:]]+/ { tot = first_float($0); print tot"\t"ro"\t"jr"\t"ls; exit }
  ' "$1"
}

make_phase_tables() {
  {
    echo -e "dataset\tbase_total\tbase_resid\tbase_jac\tbase_lin\trvv_total\trvv_resid\trvv_jac\trvv_lin\thybrid_total\thybrid_resid\thybrid_jac\thybrid_lin"
    for ds in city10000_1 city10000_3; do
      b="$(parse_timeblk "$OUT/base.$ds.log")"
      r="$(parse_timeblk "$OUT/rvv.$ds.log")"
      h="$(parse_timeblk "$OUT/hyb.$ds.log")"
      echo -e "$ds\t$b\t$r\t$h"
    done
  } > "$OUT/phase_compare.tsv"

  awk -F'\t' '
    NR==1 {
      print "dataset\ttotal_rvv_pct\tjac_rvv_pct\tlin_rvv_pct\ttotal_hyb_pct\tjac_hyb_pct\tlin_hyb_pct";
      next
    }
    {
      bt=$2; bj=$4; bl=$5;
      rt=$6; rj=$8; rl=$9;
      ht=$10; hj=$12; hl=$13;

      tr=(bt>0?(rt-bt)/bt*100.0:0);
      jr=(bj>0?(rj-bj)/bj*100.0:0);
      lr=(bl>0?(rl-bl)/bl*100.0:0);

      th=(bt>0?(ht-bt)/bt*100.0:0);
      jh=(bj>0?(hj-bj)/bj*100.0:0);
      lh=(bl>0?(hl-bl)/bl*100.0:0);

      printf "%s\t%+.2f\t%+.2f\t%+.2f\t%+.2f\t%+.2f\t%+.2f\n", $1, tr, jr, lr, th, jh, lh;
    }
  ' "$OUT/phase_compare.tsv" > "$OUT/phase_delta.tsv"
}

make_perf_diffs() {
  [[ "$DO_PERF" == "1" ]] || return 0

  for ds in city10000_1 city10000_3; do
    perf diff -c ratio -s symbol,dso "$OUT/base.$ds.data" "$OUT/rvv.$ds.data" \
      > "$OUT/diff.base_vs_rvv.$ds.txt" || true
    perf diff -c ratio -s symbol,dso "$OUT/base.$ds.data" "$OUT/hyb.$ds.data" \
      > "$OUT/diff.base_vs_hyb.$ds.txt" || true
    perf diff -c ratio -s symbol,dso "$OUT/rvv.$ds.data" "$OUT/hyb.$ds.data" \
      > "$OUT/diff.rvv_vs_hyb.$ds.txt" || true

    # 关键符号过滤
    grep -E "AutoDifferentiate|generic_dense_assignment_kernel|factorize_preordered|InnerProductComputer|ResidualBlock::Evaluate" \
      "$OUT/diff.base_vs_hyb.$ds.txt" > "$OUT/diff.base_vs_hyb.$ds.key.txt" || true
  done
}

maybe_build_hybrid
run_one base city10000_1 "$BASE_EXE" "$CASE1"
run_one rvv  city10000_1 "$RVV_EXE"  "$CASE1"
run_one hyb  city10000_1 "$HYB_EXE"  "$CASE1"

run_one base city10000_3 "$BASE_EXE" "$CASE3"
run_one rvv  city10000_3 "$RVV_EXE"  "$CASE3"
run_one hyb  city10000_3 "$HYB_EXE"  "$CASE3"

make_phase_tables
make_perf_diffs

echo "=== phase_delta (base as reference) ==="
column -t -s $'\t' "$OUT/phase_delta.tsv" || true
echo
echo "Wrote:"
echo "  $OUT/phase_compare.tsv"
echo "  $OUT/phase_delta.tsv"
if [[ "$DO_PERF" == "1" ]]; then
  echo "  $OUT/diff.*.txt (and *.key.txt)"
fi
echo "Latest OUT path saved to:"
echo "  $HOME/results/ceres_pose_graph_2d/repro_hybrid_latest_path.txt"
echo "OUT=$OUT"