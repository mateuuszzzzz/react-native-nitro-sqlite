#pragma once

#include <sqlite3.h>
#include <string>

namespace margelo::rnnitrosqlite {

struct CipherHmacFamily {
  std::string family;    // "SHA256" or "SHA512"
  bool alreadyPersisted;
};

CipherHmacFamily applyCipherHmacFamily(sqlite3* db, const std::string& dbPath);

void persistCipherHmacFamilyIfNeeded(const std::string& dbPath, const CipherHmacFamily& chosen);

void removeCipherHmacFamilySidecar(const std::string& dbPath);

} // namespace margelo::rnnitrosqlite
