cmake_minimum_required(VERSION 3.13)
project(RNNitroSQLite)

set (CMAKE_VERBOSE_MAKEFILE ON)
set (CMAKE_CXX_STANDARD 20)

add_definitions(
  ${SQLITE_FLAGS}
)

# When SQLCipher is enabled we compile the SQLCipher amalgamation
# (cpp/sqlcipher) instead of the bundled vanilla SQLite (cpp/sqlite) and
# link it against a prebuilt OpenSSL libcrypto. Both amalgamations expose a
# `sqlite3.h`; the include dir below selects which one is used.
if (NITRO_SQLITE_SQLCIPHER)
  set(SQLITE_INCLUDE_DIR ../cpp/sqlcipher)
else()
  set(SQLITE_INCLUDE_DIR ../cpp/sqlite)
endif()

file(GLOB_RECURSE cpp_files RELATIVE ${CMAKE_SOURCE_DIR}
  "../cpp/**.c"
  "../cpp/**.cpp"
  "cpp-adapter.cpp"
)

# Only ever compile a single sqlite3.c amalgamation: drop the one that is not
# selected so its translation unit does not collide with the other.
if (NITRO_SQLITE_SQLCIPHER)
  list(FILTER cpp_files EXCLUDE REGEX "cpp/sqlite/sqlite3\\.c$")
else()
  list(FILTER cpp_files EXCLUDE REGEX "cpp/sqlcipher/sqlite3\\.c$")
endif()

# Create library "RNNitroSQLite" and add all C++ files to it
add_library(${CMAKE_PROJECT_NAME} SHARED
  ${cpp_files}
)

include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/RNNitroSQLite+autolinking.cmake)

# Specifies a path to native header files.
include_directories(
  ../cpp
  ../cpp/hybridObjects
  ${SQLITE_INCLUDE_DIR}
  src/main/cpp
)

set_target_properties(
  ${CMAKE_PROJECT_NAME} PROPERTIES
  CXX_STANDARD ${CMAKE_CXX_STANDARD}
  CXX_EXTENSIONS OFF
  POSITION_INDEPENDENT_CODE ON
)

find_package(ReactAndroid REQUIRED CONFIG)
find_package(fbjni REQUIRED CONFIG)
find_library(LOG_LIB log)

target_link_libraries(
  ${CMAKE_PROJECT_NAME}
  ${LOG_LIB}
  android
  fbjni::fbjni
  ReactAndroid::jsi
)

# https://github.com/react-native-community/discussions-and-proposals/discussions/816
# This if-then-else can be removed once this library does not support version below .76
if (REACTNATIVE_MERGED_SO OR ReactAndroid_VERSION_MINOR GREATER_EQUAL 76)
  target_link_libraries(
    ${CMAKE_PROJECT_NAME}
    ReactAndroid::reactnative
  )
else()
  target_link_libraries(
    ${CMAKE_PROJECT_NAME}
    ReactAndroid::turbomodulejsijni
    ReactAndroid::react_nativemodule_core
  )
endif()

target_compile_options(
  ${CMAKE_PROJECT_NAME}
  PRIVATE
  -fexceptions
  -frtti
  -fstack-protector-all
  -O2
  -Wall
  -DONANDROID
)

# SQLCipher: enable the codec and link the prebuilt OpenSSL libcrypto for the
# current ABI. NITRO_SQLITE_OPENSSL_ROOT/<abi>/{include,lib/libcrypto.a} is
# provisioned by the `extractOpenSSL` Gradle task before the native build runs.
if (NITRO_SQLITE_SQLCIPHER)
  if (NOT NITRO_SQLITE_OPENSSL_ROOT)
    message(FATAL_ERROR "NITRO_SQLITE_SQLCIPHER is set but NITRO_SQLITE_OPENSSL_ROOT was not provided")
  endif()

  set(OPENSSL_ABI_DIR ${NITRO_SQLITE_OPENSSL_ROOT}/${ANDROID_ABI})
  if (NOT EXISTS ${OPENSSL_ABI_DIR}/lib/libcrypto.a)
    message(FATAL_ERROR "Prebuilt libcrypto.a not found at ${OPENSSL_ABI_DIR}/lib/libcrypto.a")
  endif()

  target_compile_definitions(
    ${CMAKE_PROJECT_NAME}
    PRIVATE
    SQLITE_HAS_CODEC
    SQLCIPHER_CRYPTO_OPENSSL
    SQLITE_TEMP_STORE=2
  )

  add_library(openssl_crypto STATIC IMPORTED)
  set_target_properties(openssl_crypto PROPERTIES
    IMPORTED_LOCATION ${OPENSSL_ABI_DIR}/lib/libcrypto.a)

  target_include_directories(
    ${CMAKE_PROJECT_NAME}
    PRIVATE
    ${OPENSSL_ABI_DIR}/include
  )

  target_link_libraries(
    ${CMAKE_PROJECT_NAME}
    openssl_crypto
  )
endif()
