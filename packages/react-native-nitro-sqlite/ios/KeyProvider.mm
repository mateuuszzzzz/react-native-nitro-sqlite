#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "KeyProvider.hpp"

using namespace margelo::rnnitrosqlite;

// iOS implementation of the SQLCipher key provider, backed by the Keychain.
//
// The key material (32 random bytes, hex-encoded) is generated with
// SecRandomCopyBytes and stored as a generic password item, protected with
// kSecAttrAccessibleWhenUnlockedThisDeviceOnly (available only while the device
// is unlocked, never synced/backed up to another device). The raw key never
// crosses into JavaScript: it is produced here and consumed by sqlite3_key().

namespace {

constexpr size_t kKeyLengthBytes = 32;
NSString* const kKeychainService = @"com.margelo.rnnitrosqlite.keys";

NSDictionary* baseQuery(const std::string& keyId) {
  NSString* account = [NSString stringWithUTF8String:keyId.c_str()];
  return @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrService : kKeychainService,
    (__bridge id)kSecAttrAccount : account,
  };
}

std::string toHex(const uint8_t* bytes, size_t length) {
  static const char* digits = "0123456789abcdef";
  std::string hex;
  hex.reserve(length * 2);
  for (size_t i = 0; i < length; i++) {
    hex.push_back(digits[(bytes[i] >> 4) & 0xF]);
    hex.push_back(digits[bytes[i] & 0xF]);
  }
  return hex;
}

// Reads the stored key for keyId. Returns std::nullopt when the item does not
// exist. Throws (via *outError) only communicated by returning a status.
KeyResolveResult readKey(const std::string& keyId) {
  NSMutableDictionary* query = [baseQuery(keyId) mutableCopy];
  query[(__bridge id)kSecReturnData] = @YES;
  query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

  if (status == errSecItemNotFound) {
    return KeyResolveResult::unavailable();
  }
  if (status != errSecSuccess) {
    return KeyResolveResult::error([[NSString stringWithFormat:@"Keychain read failed (OSStatus %d)", (int)status] UTF8String]);
  }

  NSData* data = (__bridge_transfer NSData*)result;
  std::string hex(reinterpret_cast<const char*>(data.bytes), data.length);
  return KeyResolveResult::ok(hex);
}

KeyResolveResult generateAndStoreKey(const std::string& keyId) {
  uint8_t raw[kKeyLengthBytes];
  if (SecRandomCopyBytes(kSecRandomDefault, kKeyLengthBytes, raw) != errSecSuccess) {
    return KeyResolveResult::error("Failed to generate secure random key material.");
  }

  std::string hex = toHex(raw, kKeyLengthBytes);
  NSData* keyData = [NSData dataWithBytes:hex.data() length:hex.size()];

  NSMutableDictionary* query = [baseQuery(keyId) mutableCopy];
  query[(__bridge id)kSecValueData] = keyData;
  query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;

  OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
  if (status != errSecSuccess) {
    return KeyResolveResult::error([[NSString stringWithFormat:@"Keychain write failed (OSStatus %d)", (int)status] UTF8String]);
  }

  return KeyResolveResult::ok(hex);
}

KeyResolveResult resolveKey(const std::string& keyId, bool dbExists) {
  KeyResolveResult existing = readKey(keyId);
  if (existing.status == KeyResolveStatus::Ok || existing.status == KeyResolveStatus::Error) {
    return existing;
  }

  // No key stored for this keyId.
  if (dbExists) {
    // The database already exists but its key is gone: do NOT generate a new
    // one, that would make the encrypted data permanently unreadable.
    return KeyResolveResult::unavailable("the key is missing from the Keychain");
  }

  return generateAndStoreKey(keyId);
}

} // namespace

namespace margelo::rnnitrosqlite {

// Called directly from sqliteOpenDb (C++); resolved by the linker at build
// time, so no runtime registration is needed.
KeyResolveResult resolvePlatformEncryptionKey(const std::string& keyId, bool dbExists) {
  return resolveKey(keyId, dbExists);
}

} // namespace margelo::rnnitrosqlite
