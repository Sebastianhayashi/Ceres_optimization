#include <iostream>
#include <Eigen/Core>
int main() {
  std::cout << "__riscv_vector=";
#ifdef __riscv_vector
  std::cout << __riscv_vector << "\n";
#else
  std::cout << "not_defined\n";
#endif

  std::cout << "EIGEN_RISCV64_USE_RVV10=";
#ifdef EIGEN_RISCV64_USE_RVV10
  std::cout << EIGEN_RISCV64_USE_RVV10 << "\n";
#else
  std::cout << "not_defined\n";
#endif
  return 0;
}
