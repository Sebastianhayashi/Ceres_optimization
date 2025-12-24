#include <iostream>
#include <Eigen/Core>

#define SHOW_MACRO(name) do { \
  std::cout << #name << "="; \
  /* gcc/clang: undefined macro can't be tested directly, use #ifdef */ \
  } while(0)

int main() {
  std::cout << "===== Eigen / RVV compile-time check =====\n";
  std::cout << "EIGEN_VERSION=" << EIGEN_WORLD_VERSION << "." << EIGEN_MAJOR_VERSION << "." << EIGEN_MINOR_VERSION << "\n";
  std::cout << "VERSION=" << __VERSION__ << "\n";
  std::cout << "GNUC=" << __GNUC__ << " GNUC_MINOR=" << __GNUC_MINOR__ << " GNUC_PATCHLEVEL=" << __GNUC_PATCHLEVEL__ << "\n";

#ifdef EIGEN_VECTORIZE
  std::cout << "EIGEN_VECTORIZE=" << EIGEN_VECTORIZE << "\n";
#else
  std::cout << "EIGEN_VECTORIZE=not_defined\n";
#endif

#ifdef EIGEN_VECTORIZE_RVV10
  std::cout << "EIGEN_VECTORIZE_RVV10=" << EIGEN_VECTORIZE_RVV10 << "\n";
#else
  std::cout << "EIGEN_VECTORIZE_RVV10=not_defined\n";
#endif

#ifdef EIGEN_VECTORIZE_RVV
  std::cout << "EIGEN_VECTORIZE_RVV=" << EIGEN_VECTORIZE_RVV << "\n";
#else
  std::cout << "EIGEN_VECTORIZE_RVV=not_defined\n";
#endif

#ifdef EIGEN_RISCV64_USE_RVV10
  std::cout << "EIGEN_RISCV64_USE_RVV10=" << EIGEN_RISCV64_USE_RVV10 << "\n";
#else
  std::cout << "EIGEN_RISCV64_USE_RVV10=not_defined\n";
#endif

#ifdef __riscv
  std::cout << "__riscv=" << __riscv << "\n";
#else
  std::cout << "__riscv=not_defined\n";
#endif

#ifdef __riscv_vector
  std::cout << "__riscv_vector=" << __riscv_vector << "\n";
#else
  std::cout << "__riscv_vector=not_defined\n";
#endif

#ifdef __riscv_v_fixed_vlen
  std::cout << "__riscv_v_fixed_vlen=" << __riscv_v_fixed_vlen << "\n";
#else
  std::cout << "__riscv_v_fixed_vlen=not_defined\n";
#endif

  std::cout << "sizeof(void*)=" << sizeof(void*) << "\n";
  std::cout << "===== end =====\n";
  return 0;
}