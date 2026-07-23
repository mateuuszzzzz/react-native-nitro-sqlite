#include "deviceMemory.hpp"
#include <string>
#if defined(__APPLE__)
#include <os/proc.h>
#elif defined(__linux__)
#include <fstream>
#include <sstream>
#endif

namespace margelo::rnnitrosqlite {

double getAvailableMemoryBytes() {
#if defined(__APPLE__)
  // Bytes this app can still allocate before iOS jetsams it (0 if unavailable → caller treats as unknown).
  return static_cast<double>(os_proc_available_memory());
#elif defined(__linux__)
  // Kernel's available-memory estimate from /proc/meminfo "MemAvailable" (kB).
  std::ifstream meminfo("/proc/meminfo");
  std::string line;
  const std::string key = "MemAvailable:";
  while (std::getline(meminfo, line)) {
    if (line.compare(0, key.size(), key) == 0) {
      std::istringstream iss(line.substr(key.size()));
      double kb = 0;
      iss >> kb;
      return kb > 0 ? kb * 1024.0 : -1;
    }
  }
  return -1;
#else
  return -1;
#endif
}

} // namespace margelo::rnnitrosqlite
