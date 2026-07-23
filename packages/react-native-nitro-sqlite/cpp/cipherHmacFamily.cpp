#include "cipherHmacFamily.hpp"
#include "NitroSQLiteException.hpp"
#include <cstdio>
#include <fstream>
#if defined(__aarch64__) && defined(__linux__)
#include <sys/auxv.h>
#include <asm/hwcap.h>
#ifndef HWCAP_SHA512
#define HWCAP_SHA512 (1 << 21)
#endif
#endif

namespace margelo::rnnitrosqlite {

namespace {

// Probed only on Android arm64, where chips without hw SHA-512 run it in slow software; elsewhere keep SQLCipher's SHA-512 default.
bool cpuSupportsSha512() {
#if defined(__aarch64__) && defined(__linux__)
  return (getauxval(AT_HWCAP) & HWCAP_SHA512) != 0;
#else
  return true;
#endif
}

// The HMAC/KDF family is recorded in a plaintext sidecar (<dbPath>.hmacalgo): it must be known BEFORE the db can be decrypted, and must stay fixed for the db's lifetime.
std::string readPersistedCipherHmacFamily(const std::string& dbPath) {
  std::ifstream sidecarIn(dbPath + ".hmacalgo");
  if (sidecarIn) {
    std::string persisted;
    std::getline(sidecarIn, persisted);
    if (persisted == "SHA256" || persisted == "SHA512") {
      return persisted;
    }
  }
  return "";
}

} // namespace

CipherHmacFamily applyCipherHmacFamily(sqlite3* db, const std::string& dbPath) {
  std::string family = readPersistedCipherHmacFamily(dbPath);
  const bool alreadyPersisted = !family.empty();
  if (family.empty()) {
    family = cpuSupportsSha512() ? "SHA512" : "SHA256";
  }
  if (family == "SHA256") {
    if (sqlite3_exec(db, "PRAGMA cipher_hmac_algorithm = HMAC_SHA256;", nullptr, nullptr, nullptr) != SQLITE_OK ||
        sqlite3_exec(db, "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA256;", nullptr, nullptr, nullptr) != SQLITE_OK) {
      const std::string message = sqlite3_errmsg(db);
      sqlite3_close_v2(db);
      throw NitroSQLiteException(NitroSQLiteExceptionType::DatabaseCannotBeOpened,
                                 "Could not configure the SQLCipher HMAC/KDF algorithm: " + message);
    }
  }
  return {family, alreadyPersisted};
}

void persistCipherHmacFamilyIfNeeded(const std::string& dbPath, const CipherHmacFamily& chosen) {
  if (chosen.alreadyPersisted) {
    return;
  }
  std::ofstream sidecarOut(dbPath + ".hmacalgo", std::ios::trunc);
  if (sidecarOut) {
    sidecarOut << chosen.family;
  }
}

void removeCipherHmacFamilySidecar(const std::string& dbPath) {
  remove((dbPath + ".hmacalgo").c_str());
}

} // namespace margelo::rnnitrosqlite
