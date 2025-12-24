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

INC_BASE="$DEPS_BASE/include/eigen3"
INC_RVV="$DEPS_RVV/include/eigen3"

rm -f /tmp/eigen_check_base /tmp/eigen_check_rvv

# base：必须 __riscv_vector=0（等价于“无 RVV 指令能力”）
g++ $FLAGS_BASE -I"$INC_BASE" /tmp/eigen_rvv_check.cc -o /tmp/eigen_check_base
/tmp/eigen_check_base

# rvv：必须 __riscv_vector=1 且 EIGEN_RISCV64_USE_RVV10 生效
g++ $FLAGS_RVV $RVV_DEFINES -I"$INC_RVV" /tmp/eigen_rvv_check.cc -o /tmp/eigen_check_rvv
/tmp/eigen_check_rvv
```



#### 3.2 编译 ceres

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
# ---- Ceres base（链接 base Eigen，且整体无 RVV 指令：FLAGS_BASE）----
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
ninja -C build-base install
```

编译 ceres rvv：

```
# ---- Ceres rvv（链接 RVV Eigen + 显式宏：FLAGS_RVV + RVV_DEFINES）----
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
ninja -C build-rvv install
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




