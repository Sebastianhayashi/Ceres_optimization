# Ceres_optimization

## 背景

## 准备

### 0 工作空间

本实验的工作空间分为以下几个部分：

- `~/cartodeps/`
    - `base/`：Baseline 依赖栈安装前缀（Eigen-base + Ceres-base）
    - `rvv/`：RVV 依赖栈安装前缀（Eigen-MR2030 + Ceres-rvv）
- `~/eigen-rvv-exp/`
    - `eigen/`：Eigen 主仓库 clone（含 `.git`）
        - `eigen-base/`：worktree，baseline（merge-base）
        - `eigen-rvv/`：worktree，MR2030
- `~/ceres-solver/`：Ceres 源码（单份）
    - `build-base/`：用 `~/cartodeps/base` 编译安装的构建目录
    - `build-rvv/`：用 `~/cartodeps/rvv` 编译安装的构建目录
- `~/cartographer_ws/`
    - `src/`
        - `cartographer/`（oe-fix）
        - `cartographer_ros/`（oe-fix，可作为第二阶段）
    - `build-base/`：Cartographer baseline build（链接 base 栈）
    - `build-rvv/`：Cartographer rvv build（链接 rvv 栈）
- `~/datasets/`
    - `g2o/`：`.g2o` 数据集
- `~/results/`
    - `ceres_pose_graph_2d/`：日志、统计、图表等输出（base vs rvv）

> 如要根据本文进行复现，请先提前准备好如上文件结构。

```
# prepare folders


mkdir -p \
  ~/cartodeps/{base,rvv} \
  ~/eigen-rvv-exp \
  ~/cartographer_ws/{src,build-base,build-rvv} \
  ~/datasets/g2o \
  ~/results/ceres_pose_graph_2d
```

### 1 依赖准备

系统中默认的 gcc 版本为 12，但是为了保持与 [eigen-compare](https://github.com/Sebastianhayashi/eigen-compare) 一样的环境，统一使用 gcc 14:

```
## gcc version in system

[openeuler@oerv-bpi-f3 eigen-rvv]$ gcc --version
gcc (GCC) 12.3.1 (openEuler 12.3.1-93.oe2403sp2)
Copyright (C) 2022 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

[openeuler@oerv-bpi-f3 eigen-rvv]$ g++ --version
g++ (GCC) 12.3.1 (openEuler 12.3.1-93.oe2403sp2)
Copyright (C) 2022 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

[openeuler@oerv-bpi-f3 eigen-rvv]$
```

根据 [openEuler 官方文档](https://docs.openeuler.org/zh/docs/24.09/docs/GCC/GCC14%E5%89%AF%E7%89%88%E6%9C%AC%E7%BC%96%E8%AF%91%E5%B7%A5%E5%85%B7%E9%93%BE%E7%94%A8%E6%88%B7%E6%8C%87%E5%8D%97.html)的说法的话，如果系统没有/不可用 SCL，就用：`source /opt/openEuler/gcc-toolset-14/enable`。
这里也默认采取 source 的方式，因为 scl 配置（如 sudo）起来会有些麻烦，不如直接 source。

安装 gcc14：

```
sudo dnf update -y

sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y git cmake

sudo dnf install -y gcc-toolset-14-gcc* gcc-toolset-14-binutils*

sudo dnf install -y scl-utils scl-utils-build

sudo dnf install -y \
  gcc-toolset-14-gcc-c++ \
  gcc-toolset-14-libgcc \
  gcc-toolset-14-libstdc++ \
  gcc-toolset-14-libstdc++-devel

```

准备系统级依赖：

```
# ===== 系统级依赖（当时“必备依赖”清单）=====
sudo dnf update -y

# 基础工具（流程里明确写过）
sudo dnf install -y git cmake ninja-build pkgconf-pkg-config

# Ceres/Cartographer 常用依赖（流程里明确写过）
sudo dnf install -y \
  boost-devel \
  abseil-cpp-devel \
  cairo-devel \
  gflags-devel \
  glog-devel \
  lua-devel \
  protobuf-devel \
  gmock-devel gtest-devel \
  python3-sphinx

```




### 2 准备源码

```
cd ~/eigen-rvv-exp

git clone https://gitlab.com/libeigen/eigen.git eigen
cd eigen

# 拉 MR2030 head 到本地分支
git fetch origin refs/merge-requests/2030/head:rvv-mr2030
git fetch origin master

# 计算 MR2030 与 master 的公共祖先作为 baseline
BASE_SHA=$(git merge-base rvv-mr2030 origin/master)
echo "BASE_SHA=$BASE_SHA"

# 用 worktree 生成两份源码（不重复下载）
git worktree add eigen-base "$BASE_SHA"
git worktree add eigen-rvv  rvv-mr2030
```

验证两份源码确实存在：

```bash
cd ~/eigen-rvv-exp/eigen/eigen-base && git rev-parse --short HEAD
cd ~/eigen-rvv-exp/eigen/eigen-rvv  && git rev-parse --short HEAD
```

预期输出：

```
[openeuler@oerv-bpi-f3 eigen-rvv-exp]$ cd ~/eigen-rvv-exp/eigen/eigen-base && git rev-parse --short HEAD
196eed3d6
[openeuler@oerv-bpi-f3 eigen-base]$ cd ~/eigen-rvv-exp/eigen/eigen-rvv  && git rev-parse --short HEAD
5a4f568de
[openeuler@oerv-bpi-f3 eigen-rvv]$
```

### 3 环境配置

环境的配置是直接沿用 [eigen-compare](https://github.com/Sebastianhayashi/eigen-compare) 下面的环境变量。

```
# ===== base（无 RVV 加速：不额外启用 EIGEN_RISCV64_USE_RVV10）=====

# 进入 gcc14 环境
source /opt/openEuler/gcc-toolset-14/enable

# 依赖前缀（base）
export DEPS_BASE="$HOME/cartodeps/base"
mkdir -p "$DEPS_BASE"

# 编译器
export CC=gcc
export CXX=g++

# 固定编译变量（与 rvv 保持一致，便于公平对比）
export RVV_FLAGS="-march=rv64gcv_zvl256b -mabi=lp64d -mrvv-vector-bits=zvl"
export OPT_FLAGS="-O3 -DNDEBUG -ffast-math -fno-math-errno -fno-trapping-math -funroll-loops"
export CFLAGS="${OPT_FLAGS} ${RVV_FLAGS}"
export CXXFLAGS="${OPT_FLAGS} ${RVV_FLAGS}"

# （可选）Eigen include 约定路径
export INC_BASE="$DEPS_BASE/include/eigen3"
```

```
# ===== rvv（有 RVV 加速：额外启用 EIGEN_RISCV64_USE_RVV10）=====

# 进入 gcc14 环境
source /opt/openEuler/gcc-toolset-14/enable

# 依赖前缀（rvv）
export DEPS_RVV="$HOME/cartodeps/rvv"
mkdir -p "$DEPS_RVV"

# 编译器
export CC=gcc
export CXX=g++

# 固定编译变量（与 base 保持一致，便于公平对比）
export RVV_FLAGS="-march=rv64gcv_zvl256b -mabi=lp64d -mrvv-vector-bits=zvl"
export OPT_FLAGS="-O3 -DNDEBUG -ffast-math -fno-math-errno -fno-trapping-math -funroll-loops"
export CFLAGS="${OPT_FLAGS} ${RVV_FLAGS}"
export CXXFLAGS="${OPT_FLAGS} ${RVV_FLAGS}"

# 仅 RVV 栈额外加的宏（关键区别）
export RVV_DEFINES="-DEIGEN_RISCV64_USE_RVV10"

# （可选）Eigen include 约定路径
export INC_RVV="$DEPS_RVV/include/eigen3"
```

#### 3.1 ar 库缺失

在 Ninja 已经编译出大量 .o，在生成 lib/libceres.a 这类静态库时触发 ranlib/ar，随后 toolset 的 ar 启动失败：

```
... && /opt/openEuler/gcc-toolset-14/root/usr/bin/ranlib lib/libceres.a && :
/opt/openEuler/gcc-toolset-14/root/usr/bin/ar: error while loading shared libraries: libbfd-2.42.so: cannot open shared object file: No such file or directory
ninja: build stopped: subcommand failed.
```

后续通过 ldd 验证的时候发现 ar 就是缺少的：

```
ldd /opt/openEuler/gcc-toolset-14/root/usr/bin/ar | grep -E "bfd|not found" || true

libbfd-2.42.so => not found
```

但是/ usr/bin/ar 正常（用的是 libbfd-2.41.so）：

```
ldd /usr/bin/ar | grep -E "bfd|not found" || true

libbfd-2.41.so => /usr/lib64/libbfd-2.41.so (...)
```

解决办法就是用系统中的 ar：

```
export LD_LIBRARY_PATH=/opt/openEuler/gcc-toolset-14/root/usr/lib64:$LD_LIBRARY_PATH
ldd /opt/openEuler/gcc-toolset-14/root/usr/bin/ar | grep libbfd
```

### 3 编译

这里的编译顺序为：eigen -> ceres。

在开始进入编译阶段前注意需要手动开启 swap，曾经出现过在编译 ceres 的时候出现爆内存整个系统死掉的情况。所以开始编译前先给系统分配 8G swap：

```
# 1) 加 8GB swap
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 验证 swap 已启用
swapon --show
free -h
```

#### 3.1 编译 eigen

下面为编译 eigen 全流程：

```
# ============================================================
# 0) 进入 GCC 14 toolset
# ============================================================
source /opt/openEuler/gcc-toolset-14/enable
export CC=gcc
export CXX=g++

# ============================================================
# 1) 统一优化参数（只在 march 上区分 base vs rvv）
#    base：明确无 RVV 指令  -> -march=rv64gc
#    rvv ：带 RVV 指令      -> -march=rv64gcv_zvl256b + -mrvv-vector-bits=zvl
# ============================================================
OPT_FLAGS="-O3 -DNDEBUG -ffast-math -fno-math-errno -fno-trapping-math -funroll-loops"

FLAGS_BASE="${OPT_FLAGS} -march=rv64gc -mabi=lp64d"
FLAGS_RVV="${OPT_FLAGS} -march=rv64gcv_zvl256b -mabi=lp64d -mrvv-vector-bits=zvl"
RVV_DEFINES="-DEIGEN_RISCV64_USE_RVV10"

# ============================================================
# 2) 两套 prefix（你要求：base/rvv 命名固定，不再用 rvv-non 之类）
# ============================================================
export DEPS_BASE="$HOME/cartodeps/base"
export DEPS_RVV="$HOME/cartodeps/rvv"
mkdir -p "$DEPS_BASE" "$DEPS_RVV"

# 你们当时 Eigen 源码目录约定（如不同，改这两行即可）
EIGEN_BASE_SRC="$HOME/eigen-rvv-exp/eigen/eigen-base"
EIGEN_RVV_SRC="$HOME/eigen-rvv-exp/eigen/eigen-rvv"

# ============================================================
# 3) 安装两套 Eigen（仅生成 CMake package；关掉 BLAS/LAPACK 等）
# ============================================================
cd "$EIGEN_BASE_SRC"
rm -rf build-install
cmake -S . -B build-install -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$DEPS_BASE" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FLAGS_BASE" \
  -DCMAKE_CXX_FLAGS="$FLAGS_BASE" \
  -DBUILD_TESTING=OFF \
  -DEIGEN_BUILD_TESTING=OFF \
  -DEIGEN_BUILD_BLAS=OFF \
  -DEIGEN_BUILD_LAPACK=OFF \
  -DEIGEN_BUILD_DOC=OFF \
  -DEIGEN_BUILD_PKGCONFIG=OFF \
  -DEIGEN_BUILD_CMAKE_PACKAGE=ON
ninja -C build-install install

cd "$EIGEN_RVV_SRC"
rm -rf build-install
cmake -S . -B build-install -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$DEPS_RVV" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FLAGS_RVV" \
  -DCMAKE_CXX_FLAGS="$FLAGS_RVV" \
  -DBUILD_TESTING=OFF \
  -DEIGEN_BUILD_TESTING=OFF \
  -DEIGEN_BUILD_BLAS=OFF \
  -DEIGEN_BUILD_LAPACK=OFF \
  -DEIGEN_BUILD_DOC=OFF \
  -DEIGEN_BUILD_PKGCONFIG=OFF \
  -DEIGEN_BUILD_CMAKE_PACKAGE=ON
ninja -C build-install install

ls "$DEPS_BASE/share/eigen3/cmake/Eigen3Config.cmake"
ls "$DEPS_RVV/share/eigen3/cmake/Eigen3Config.cmake"

```

#### 3.2 检查编译结果是否干净（可选）

此前发生过不小心把参数写错，结果编译出来两份 eigen 都带有 rvv 指令的情况。所以下面准备了一份用于检查编译出来 eigen 是否干净的 [eigen_rvv_check.cc](./eigen_rvv_check.cc)。

使用方法：

```
# 0) 安全进入 gcc14（避免 set -u 影响 enable）
set +u
source /opt/openEuler/gcc-toolset-14/enable
set -u

# 1) 选择一个你肯定可写的目录（建议归档到 results）
CHECK_DIR="$HOME/results/ceres_pose_graph_2d/eigen_check"
mkdir -p "$CHECK_DIR"

# 2) 用 vi 写入 check 源码（按你习惯）
vi "$CHECK_DIR/eigen_rvv_check.cc"
```

继续编译并执行：

```
# 3) 准备变量（如果你已经在别处设过，这里不会覆盖）
OPT_FLAGS="-O3 -DNDEBUG"
FLAGS_BASE="${FLAGS_BASE:-$OPT_FLAGS -march=rv64gc -mabi=lp64d}"
FLAGS_RVV="${FLAGS_RVV:-$OPT_FLAGS -march=rv64gcv_zvl256b -mabi=lp64d -mrvv-vector-bits=zvl}"
RVV_DEFINES="${RVV_DEFINES:--DEIGEN_RISCV64_USE_RVV10}"

INC_BASE="${INC_BASE:-$HOME/cartodeps/base/include/eigen3}"
INC_RVV="${INC_RVV:-$HOME/cartodeps/rvv/include/eigen3}"
test -d "$INC_BASE"
test -d "$INC_RVV"

# 4) 编译
g++ -std=c++17 $FLAGS_BASE -I"$INC_BASE" "$CHECK_DIR/eigen_rvv_check.cc" -o "$CHECK_DIR/eigen_check_base"
g++ -std=c++17 $FLAGS_RVV  $RVV_DEFINES -I"$INC_RVV"  "$CHECK_DIR/eigen_rvv_check.cc" -o "$CHECK_DIR/eigen_check_rvv"

# 5) 运行
"$CHECK_DIR/eigen_check_base"
"$CHECK_DIR/eigen_check_rvv"
```

判定标准为：

- base 输出应包含：__riscv_vector=not_defined
- rvv 输出应包含：__riscv_vector=1 且 EIGEN_RISCV64_USE_RVV10=1

#### 3.2 编译 ceres

> ceres 在全核心的情况下编译时间预估：2～3 小时。

拉取并编译两套 Ceres：

```
cd "$HOME"
if [ ! -d "$HOME/ceres-solver/.git" ]; then
  git clone https://ceres-solver.googlesource.com/ceres-solver
fi
cd "$HOME/ceres-solver"
```

> 为了防止环境变量偷换 ar/ranlib，建议：`unset AR RANLIB NM`。

编译 ceres-base：

```
# 进入 gcc14 环境
source /opt/openEuler/gcc-toolset-14/enable

# 前缀（base）
export DEPS_BASE="$HOME/cartodeps/base"

# 编译器
export CC=gcc
export CXX=g++

# 明确区分：base=无 RVV；rvv=有 RVV（rvv 这里先不建）
export OPT_FLAGS="-O3 -DNDEBUG -ffast-math -fno-math-errno -fno-trapping-math -funroll-loops"
export FLAGS_BASE="${OPT_FLAGS} -march=rv64gc -mabi=lp64d"

# 关键：把 Ceres 自带的 abseil-cpp 子模块拉下来（否则必然回退系统 absl）
cd ~/ceres-solver
git submodule update --init --recursive
ls -la third_party/abseil-cpp | head -n 5

# 重新配置 + 编译安装（默认全核）
rm -rf build-base
cmake -S . -B build-base -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$DEPS_BASE" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FLAGS_BASE" \
  -DCMAKE_CXX_FLAGS="$FLAGS_BASE" \
  -DEigen3_DIR="$DEPS_BASE/share/eigen3/cmake" \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=ON \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib

ninja -C build-base -j"$(nproc)" install
```

编译 ceres rvv：

```
# ===== Ceres (rvv) build & install: links to Eigen in ~/cartodeps/rvv, enables RVV flags + EIGEN_RISCV64_USE_RVV10 =====
set -euxo pipefail

# 0) Enter gcc14 toolset (avoid set -u issues if you use it elsewhere)
set +u
source /opt/openEuler/gcc-toolset-14/enable
set -u

# 1) Prefix (rvv)
export DEPS_RVV="$HOME/cartodeps/rvv"
mkdir -p "$DEPS_RVV"

# 2) Compilers
export CC=gcc
export CXX=g++

# 3) RVV compile flags (rvv = with vector extension)
export OPT_FLAGS="-O3 -DNDEBUG -ffast-math -fno-math-errno -fno-trapping-math -funroll-loops"
export FLAGS_RVV="${OPT_FLAGS} -march=rv64gcv_zvl256b -mabi=lp64d -mrvv-vector-bits=zvl"
export RVV_DEFINES="-DEIGEN_RISCV64_USE_RVV10"

# 4) Ensure bundled abseil submodule is present (avoids missing abslConfig.cmake)
cd "$HOME/ceres-solver"
git submodule update --init --recursive

# 5) Configure + build (full cores) + install
rm -rf build-rvv
cmake -S . -B build-rvv -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$DEPS_RVV" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FLAGS_RVV" \
  -DCMAKE_CXX_FLAGS="$FLAGS_RVV $RVV_DEFINES" \
  -DEigen3_DIR="$DEPS_RVV/share/eigen3/cmake" \
  -DBUILD_TESTING=OFF \
  -DBUILD_EXAMPLES=ON \
  -DCMAKE_AR=/usr/bin/ar \
  -DCMAKE_RANLIB=/usr/bin/ranlib

ninja -C build-rvv -j"$(nproc)" install

# 6) Sanity check: ensure this build was configured against the RVV prefix Eigen
grep -E "Eigen3_DIR:PATH=" -n build-rvv/CMakeCache.txt || true
```

核对一下是否正确：

```
# 强制核对：两套 Ceres 的 Eigen3_DIR 必须指向不同 prefix
grep -E "Eigen3_DIR:PATH=" -n build-base/CMakeCache.txt
grep -E "Eigen3_DIR:PATH=" -n build-rvv/CMakeCache.txt
```
#### 3.3 编译 cartographer

```
mkdir -p "$HOME/cartographer_ws/src"
cd "$HOME/cartographer_ws/src"
if [ ! -d "$HOME/cartographer_ws/src/cartographer/.git" ]; then
  git clone -b oe-fix https://github.com/discodyer/cartographer.git
fi

# 自动探测 ceres_DIR（lib 或 lib64）
CERES_DIR_BASE="$(dirname "$(find "$DEPS_BASE" -name CeresConfig.cmake | head -n 1)")"
CERES_DIR_RVV="$(dirname "$(find "$DEPS_RVV"  -name CeresConfig.cmake | head -n 1)")"
test -n "$CERES_DIR_BASE"
test -n "$CERES_DIR_RVV"

cd "$HOME/cartographer_ws/src/cartographer"

# Cartographer base
rm -rf build-base
cmake -S . -B build-base -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FLAGS_BASE" \
  -DCMAKE_CXX_FLAGS="$FLAGS_BASE" \
  -DCMAKE_PREFIX_PATH="$DEPS_BASE" \
  -DEigen3_DIR="$DEPS_BASE/share/eigen3/cmake" \
  -Dceres_DIR="$CERES_DIR_BASE" \
  -DBUILD_TESTING=OFF
ninja -C build-base

# Cartographer rvv
rm -rf build-rvv
cmake -S . -B build-rvv -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FLAGS_RVV" \
  -DCMAKE_CXX_FLAGS="$FLAGS_RVV $RVV_DEFINES" \
  -DCMAKE_PREFIX_PATH="$DEPS_RVV" \
  -DEigen3_DIR="$DEPS_RVV/share/eigen3/cmake" \
  -Dceres_DIR="$CERES_DIR_RVV" \
  -DBUILD_TESTING=OFF
ninja -C build-rvv
```

## 测试数据集选取

获取数据集：

```
# 获取 planar pose graph 的 g2o 数据集
cd ~
git clone https://github.com/corelabuf/planar_pgo_datasets.git

# 查看数据文件（仓库内 datasets 目录）
cd ~/planar_pgo_datasets/datasets
ls -lh *.g2o | head
```

### 选取的理由

我们的目的是：把 Eigen RVV patch 对 Ceres（再到 Cartographer）的性能影响。

也就是我们在选择数据集的时候标准为：最小化系统噪声、最大化命中线性代数热路径、便于重复统计。所以对于数据集而言，需要具备下面的特性：

- 多规模 + 多噪声
- 计算结构匹配
- 输入格式（.g2o）直接可用

## 性能测试

目前搜集完数据集之后，写了两个脚本来自动化测试所有数据集并且记录结果：

- [sweep_base.sh](./tools/sweep_base.sh)
- [sweep_rvv.sh](./tools/sweep_rvv.sh)

逻辑都是（唯一变量是使用的 eigen 是否带 rvv 加速指令）：

- 进入 gcc14 环境
- `DEPS_BASE=~/cartodeps/base`
- `BIN_BASE=~/ceres-solver/build-base/bin/pose_graph_2d`
- `DATA_DIR=~/planar_pgo_datasets/datasets`
- 对每个 `.g2o`：在独立目录内执行
    
    `(/usr/bin/time -v "$BIN_BASE" --input="$f") 2>&1 | tee run.log`
    
    并从 `run.log` 解析 wall time / max RSS，写入 `summary.tsv`

生成结果对比表：

```
BASE_DIR="$(ls -dt ~/results/ceres_pose_graph_2d/base_sweep_* | head -1)"
RVV_DIR="$(ls -dt  ~/results/ceres_pose_graph_2d/rvv_sweep_*  | head -1)"

phase="$RVV_DIR/phase_compare.tsv"
delta="$RVV_DIR/phase_delta.tsv"

echo -e "dataset\tbase_total\tbase_resid\tbase_jac\tbase_lin\trvv_total\trvv_resid\trvv_jac\trvv_lin" > "$phase"

extract_one() {
  awk '
    # 只抓 “Time (in seconds):” 段的关键行，避免误匹配其它文本
    $1=="Residual" && $2=="only" && $3=="evaluation" && $4 ~ /^[0-9]/ {ro=$4}
    $1=="Jacobian" && $2=="&"    && $3=="residual"  && $4=="evaluation" && $5 ~ /^[0-9]/ {jr=$5}
    $1=="Linear"   && $2=="solver" && $3 ~ /^[0-9]/ {ls=$3}
    $1=="Total" && $2 ~ /^[0-9]/ {tot=$2}
    END { printf "%s\t%s\t%s\t%s\n", tot+0, ro+0, jr+0, ls+0 }
  ' "$1"
}

for d in "$BASE_DIR"/*; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  b_log="$BASE_DIR/$name/run.log"
  r_log="$RVV_DIR/$name/run.log"
  [[ -f "$b_log" && -f "$r_log" ]] || continue
  b="$(extract_one "$b_log")"
  r="$(extract_one "$r_log")"
  echo -e "$name\t$b\t$r" >> "$phase"
done

echo "Wrote: $phase"
column -t -s $'\t' "$phase" | head -n 30

# 计算每个 phase 的变化百分比（rvv 相对 base）
awk -F'\t' '
NR==1 { print "dataset\ttotal_pct\tresid_pct\tjac_pct\tlin_pct"; next }
{
  bt=$2; br=$3; bj=$4; bl=$5;
  rt=$6; rr=$7; rj=$8; rl=$9;
  tp=(rt-bt)/bt*100.0;
  rp=(rr-br)/br*100.0;
  jp=(rj-bj)/bj*100.0;
  lp=(rl-bl)/bl*100.0;
  printf "%s\t%+.2f\t%+.2f\t%+.2f\t%+.2f\n", $1, tp, rp, jp, lp;
}
' "$phase" | tee "$delta" | column -t -s $'\t' | head -n 30

echo "Wrote: $delta"
```

表格解读规则：

- total_pct = (rvv_total - base_total) / base_total

- jac_pct = (rvv_jac - base_jac) / base_jac

- lin_pct = (rvv_lin - base_lin) / base_lin

- resid_pct = (rvv_resid - base_resid) / base_resid

```
+ 代表 RVV 比 base 慢（退化）
- 代表 RVV 比 base 快（收益）
```

### 第一次测试

```
dataset                 total_pct  resid_pct  jac_pct  lin_pct
city10000_1             +7.35      +0.09      +43.72   +0.56
city10000_2             +8.72      +1.09      +41.21   +2.54
city10000_3             +10.79     +1.42      +43.90   +6.31
city10000_4             +8.76      +1.69      +48.02   +3.27
city10000_5             +7.55      +0.65      +41.08   +2.88
city10000_ground_truth  +11.83     +1.55      +47.87   +5.54
Grid1000_1              +18.82     +3.88      +50.02   +6.21
Grid1000_2              +19.31     +2.92      +51.47   +5.25
Grid1000_3              +21.41     +3.98      +51.12   +8.52
Grid1000_4              +14.49     +2.07      +38.85   +3.00
Grid1000_5              +18.40     +1.59      +48.23   +5.77
Grid1000_ground_truth   +11.73     +1.47      +40.03   +4.40
M3500_1                 +17.46     +3.32      +47.29   +7.72
M3500_2                 +17.41     +3.76      +46.96   +8.29
M3500_3                 +8.30      -1.43      +43.90   +1.83
M3500_4                 +15.71     +3.22      +46.74   +8.71
M3500_5                 +11.12     -0.05      +44.38   +3.31
M3500_ground_truth      +10.72     +1.84      +43.59   +2.42
[openeuler@oerv-bpi-f3 ~]$
[openeuler@oerv-bpi-f3 ~]$ echo "Wrote: $delta"
Wrote: /home/openeuler/results/ceres_pose_graph_2d/rvv_sweep_20251225_090550/phase_delta.tsv
[openeuler@oerv-bpi-f3 ~]$ cat /home/openeuler/results/ceres_pose_graph_2d/rvv_sweep_20251225_090550/phase_delta.tsv
dataset	total_pct	resid_pct	jac_pct	lin_pct
city10000_1	+7.35	+0.09	+43.72	+0.56
city10000_2	+8.72	+1.09	+41.21	+2.54
city10000_3	+10.79	+1.42	+43.90	+6.31
city10000_4	+8.76	+1.69	+48.02	+3.27
city10000_5	+7.55	+0.65	+41.08	+2.88
city10000_ground_truth	+11.83	+1.55	+47.87	+5.54
Grid1000_1	+18.82	+3.88	+50.02	+6.21
Grid1000_2	+19.31	+2.92	+51.47	+5.25
Grid1000_3	+21.41	+3.98	+51.12	+8.52
Grid1000_4	+14.49	+2.07	+38.85	+3.00
Grid1000_5	+18.40	+1.59	+48.23	+5.77
Grid1000_ground_truth	+11.73	+1.47	+40.03	+4.40
M3500_1	+17.46	+3.32	+47.29	+7.72
M3500_2	+17.41	+3.76	+46.96	+8.29
M3500_3	+8.30	-1.43	+43.90	+1.83
M3500_4	+15.71	+3.22	+46.74	+8.71
M3500_5	+11.12	-0.05	+44.38	+3.31
M3500_ground_truth	+10.72	+1.84	+43.59	+2.42
```

结果：

- total_pct：大致 +7% 到 +21%（全体退化）

- resid_pct：大致 -1.4% 到 +4%（非常小）

- lin_pct：大致 +0.5% 到 +8.7%（小幅）

- jac_pct：几乎稳定在 +38% 到 +51%（巨大且一致）

也就是说：RVV 版本的整体退化（+7%~+21%）主要由 Jacobian & residual evaluation 阶段的大幅变慢（约 +40%~+51%）驱动；Linear solver 只有小幅变慢，Residual-only 影响很小。

所以来关注一下 Jacobain 对总退化贡献比例：

```
phase=/home/openeuler/results/ceres_pose_graph_2d/rvv_sweep_20251225_090550/phase_compare.tsv

awk -F'\t' '
NR==1{
  print "dataset\tbase_total\tbase_jac_share\tbase_lin_share\t"
        "total_delta_s\tjac_delta_s\tlin_delta_s\tresid_delta_s\t"
        "jac_contrib_pct\tlin_contrib_pct";
  next
}
{
  bt=$2; br=$3; bj=$4; bl=$5;
  rt=$6; rr=$7; rj=$8; rl=$9;

  dt=rt-bt; dj=rj-bj; dl=rl-bl; dr=rr-br;

  jac_share = (bt>0? 100*bj/bt : 0);
  lin_share = (bt>0? 100*bl/bt : 0);

  jac_contrib = (dt!=0? 100*dj/dt : 0);
  lin_contrib = (dt!=0? 100*dl/dt : 0);

  printf "%s\t%.3f\t%.1f%%\t%.1f%%\t%.3f\t%.3f\t%.3f\t%.3f\t%.1f%%\t%.1f%%\n",
         $1, bt, jac_share, lin_share, dt, dj, dl, dr, jac_contrib, lin_contrib;
}
' "$phase" \
| sort -t $'\t' -k9,9nr \
| column -t -s $'\t' \
| head -n 25
```

结果：

```
city10000_1             24.534      11.6%           75.4%           1.802  1.249  0.104  0.001   69.3%  5.8%
Grid1000_4              2.085       23.5%           52.9%           0.302  0.190  0.033  0.003   63.0%  11.0%
Grid1000_2              1.561       23.5%           52.3%           0.301  0.189  0.043  0.004   62.6%  14.2%
Grid1000_1              1.030       23.5%           51.5%           0.194  0.121  0.033  0.003   62.5%  17.0%
M3500_3                 5.527       11.6%           67.9%           0.458  0.282  0.069  -0.007  61.5%  15.0%
Grid1000_5              2.058       23.0%           53.5%           0.379  0.228  0.064  0.003   60.2%  16.8%
M3500_5                 6.140       14.6%           65.1%           0.683  0.397  0.132  -0.000  58.2%  19.4%
Grid1000_3              1.505       23.6%           52.1%           0.322  0.182  0.067  0.005   56.5%  20.7%
M3500_ground_truth      0.374       13.8%           32.0%           0.040  0.022  0.003  0.000   56.0%  7.2%
city10000_2             11.776      11.6%           72.8%           1.027  0.563  0.218  0.006   54.9%  21.2%
M3500_1                 11.389      19.0%           61.4%           1.988  1.024  0.540  0.029   51.5%  27.1%
city10000_4             47.064      9.1%            79.4%           4.125  2.056  1.221  0.040   49.9%  29.6%
M3500_2                 11.680      18.3%           62.1%           2.034  1.005  0.602  0.035   49.4%  29.6%
Grid1000_ground_truth   0.070       14.3%           30.7%           0.008  0.004  0.001  0.000   48.8%  11.5%
city10000_5             39.169      8.7%            79.6%           2.957  1.404  0.897  0.013   47.5%  30.3%
city10000_ground_truth  2.382       11.5%           54.4%           0.282  0.131  0.072  0.001   46.4%  25.4%
M3500_4                 6.876       14.4%           65.5%           1.080  0.462  0.392  0.019   42.8%  36.3%
city10000_3             42.415      9.0%            79.3%           4.575  1.676  2.121  0.031   36.6%  46.4%
dataset                 base_total  base_jac_share  base_lin_share
```

图表解释：

```
以任意一行（比如 city10000_1）为例，你的列含义是：

base_total：base 总耗时（秒）

base_jac_share：base 下 Jacobian 阶段占总时间比例 = base_jac / base_total

base_lin_share：base 下 Linear solver 阶段占总时间比例 = base_lin / base_total

total_delta_s：rvv 总耗时比 base 多出来的秒数 = (rvv_total - base_total)

jac_delta_s：Jacobian 阶段多出来的秒数 = (rvv_jac - base_jac)

lin_delta_s：Linear solver 多出来的秒数 = (rvv_lin - base_lin)

resid_delta_s：Residual-only 多出来的秒数 = (rvv_resid - base_resid)

jac_contrib_pct：总退化（total_delta_s）里，有多少百分比是 Jacobian 贡献的
= jac_delta_s / total_delta_s

lin_contrib_pct：同理，线性求解器对总退化的贡献
= lin_delta_s / total_delta_s
```

> 相对退化（%）”不等于“贡献度（%）。

由上表可知：

```
city10000_1：

base_total 24.534s

jac_share 11.6%，lin_share 75.4%（线性求解器本来就很大头）

total_delta_s 1.802s 里：

jac_delta_s 1.249s，占 69.3%

lin_delta_s 0.104s，占 5.8%

resid_delta_s ~0

---

city10000_3：

base_total 42.415s

jac_share 9.0%，lin_share 79.3%（线性求解器几乎占了 4/5）

total_delta_s 4.575s 里：

jac_delta_s 1.676s，占 36.6%

lin_delta_s 2.121s，占 46.4%（比 Jacobian 还多）
```

所以说：Jacobian 是“相对退化最大的阶段”，但 Linear solver 因为基线占比太高，在部分大图上会成为“绝对退化贡献最大”的阶段。

在后续的优化思路中不要指望“全局开 RVV”能自动加速稀疏分解，理由是：lin_contrib_pct >= 40%。

