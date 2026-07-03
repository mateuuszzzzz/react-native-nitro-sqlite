#pragma once

#include <string>

namespace margelo::rnnitrosqlite {

// Outcome of resolving a key for a given keyId. The raw key material never
// leaves the native layer: it is produced here and handed straight to
// sqlite3_key(), and is never exposed to JavaScript.
enum class KeyResolveStatus {
  // A key was found (or freshly generated) and `key` holds the hex-encoded
  // 32-byte key material.
  Ok,
  // No key exists for this keyId and the database file already exists, so a new
  // key must NOT be generated (that would make the existing encrypted data
  // permanently unreadable). Surfaced to JS as EncryptionKeyUnavailable.
  Unavailable,
  // The secure storage could not be accessed (e.g. Keychain/Keystore error).
  Error,
};

struct KeyResolveResult {
  KeyResolveStatus status;
  // Hex-encoded key material, only set when status == Ok.
  std::string key;
  // Optional human-readable detail for Error/Unavailable, used in the thrown
  // message.
  std::string message;

  static KeyResolveResult ok(std::string keyHex) {
    return KeyResolveResult{KeyResolveStatus::Ok, std::move(keyHex), ""};
  }
  static KeyResolveResult unavailable(std::string detail = "") {
    return KeyResolveResult{KeyResolveStatus::Unavailable, "", std::move(detail)};
  }
  static KeyResolveResult error(std::string detail) {
    return KeyResolveResult{KeyResolveStatus::Error, "", std::move(detail)};
  }
};

// Resolves the SQLCipher key for `keyId` from the platform secure storage.
// Implemented per platform:
//   - iOS: ios/KeyProvider.mm (Keychain)
//   - Android: android/cpp-adapter.cpp (JNI -> KeyProvider.kt, Keystore-backed)
//
// `dbExists` tells the implementation whether the database file is already
// present:
//   - key found            -> Ok(key)
//   - not found, !dbExists  -> generate + persist a random key, return Ok(key)
//   - not found, dbExists   -> Unavailable (do not generate)
//
// This is a plain function (not a runtime-registered hook) on purpose: the
// linker resolves the symbol at build time, so there is no load-order or
// dead-stripping problem.
KeyResolveResult resolvePlatformEncryptionKey(const std::string& keyId, bool dbExists);

} // namespace margelo::rnnitrosqlite
