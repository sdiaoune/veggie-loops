// Review-only rejection tests; no native engine or original code is loaded.
#include "../generators/three_osc_tables.hpp"
#include <iostream>
#include <limits>
#include <string>

int main(int argc, char** argv) {
  using namespace veggie_loops::three_osc;
  if (argc != 2) return 2;
  if (std::string(argv[1]) == "fft-plan") {
    try { FFTPlan invalid(-1, false); }
    catch (const std::invalid_argument&) {
      std::cout << "FFT size rejected before allocation\n"; return 0;
    } catch (const std::exception& error) {
      std::cerr << "Wrong rejection path (allocation occurred before size guard): " << error.what() << '\n';
      return 1;
    }
    return 1;
  }
  if (std::string(argv[1]) == "next-fast-size") {
    try {
      const int result = nextFastSize(std::numeric_limits<int>::max());
      std::cerr << "Unrepresentable next fast size returned: " << result << '\n'; return 1;
    } catch (const std::exception&) {
      std::cout << "Unrepresentable next fast size rejected safely\n"; return 0;
    }
  }
  return 2;
}
