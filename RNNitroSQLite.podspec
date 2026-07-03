require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
folly_compiler_flags = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1'

# TODO: Should be customizable in package.json.
# Used to create comparable benchmark results
performance_mode = 1

Pod::Spec.new do |s|
  s.name         = "RNNitroSQLite"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]
  s.platforms    = { :ios => min_ios_version_supported, :visionos => "1.0" }
  s.source       = { :git => "https://github.com/margelo/react-native-nitro-sqlite.git", :tag => "#{s.version}" }

  s.source_files = [
    # Implementation (Swift)
    "ios/**/*.{swift}",
    # Autolinking/Registration (Objective-C++)
    "ios/**/*.{h,hpp,m,mm}",
    # Implementation (C++ objects)
    "cpp/**/*.{h,hpp,c,cpp}"
  ]

# Enable with `NITRO_SQLITE_SQLCIPHER=1 pod install`. Selects the bundled
# SQLCipher amalgamation (cpp/sqlcipher) instead of vanilla SQLite (cpp/sqlite)
# and uses Apple's built-in CommonCrypto backend, so no external OpenSSL is
# required (unlike Android, which links a prebuilt libcrypto).
sqlcipher_enabled = ENV['NITRO_SQLITE_SQLCIPHER'] == '1'

# The header search path must point at the selected amalgamation's `sqlite3.h`.
sqlite_header_dir = sqlcipher_enabled ? "${PODS_TARGET_SRCROOT}/cpp/sqlcipher" : "${PODS_TARGET_SRCROOT}/cpp/sqlite"

# Force-include the symbol prefix map (sqlite3_* -> nitro_sqlite3_*) into every
# C/C++ translation unit when SQLCipher is bundled. If the host app also links
# the system libsqlite3 (any other pod using `-lsqlite3`), unprefixed calls like
# sqlite3_key() would otherwise bind to Apple's stub at link time and fail with
# "not an error". Prefixing keeps our SQLCipher fully self-contained: our code
# always calls our implementation, the rest of the app keeps the system SQLite.
sqlcipher_prefix_flag = sqlcipher_enabled ? " -include \"${PODS_TARGET_SRCROOT}/cpp/sqlcipher/sqlite3_symbol_prefix.h\"" : ""

  s.pod_target_xcconfig = {
    :GCC_PREPROCESSOR_DEFINITIONS => "HAVE_FULLFSYNC=1",
    :WARNING_CFLAGS => "-Wno-shorten-64-to-32 -Wno-comma -Wno-unreachable-code -Wno-conditional-uninitialized -Wno-deprecated-declarations",
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'DEFINES_MODULE' => 'YES',
    "HEADER_SEARCH_PATHS" => "\"${PODS_ROOT}/RCT-Folly\" \"#{sqlite_header_dir}\"",
    # NDEBUG=1 disables SQLite's internal asserts. In a CocoaPods Debug build
    # NDEBUG is otherwise undefined, which activates asserts referencing struct
    # members (e.g. EdupBuf.zEnd) that only exist under SQLITE_DEBUG -> a
    # compile error. Defining NDEBUG keeps the amalgamation building in both
    # Debug and Release (matches how Android compiles it with -O2/no asserts).
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) FOLLY_NO_CONFIG FOLLY_CFG_NO_COROUTINES" + (sqlcipher_enabled ? " SQLITE_HAS_CODEC SQLCIPHER_CRYPTO_CC SQLITE_TEMP_STORE=2 NDEBUG=1" : ""),
    "OTHER_CFLAGS" => "$(inherited)" + sqlcipher_prefix_flag,
    "OTHER_CPLUSPLUSFLAGS" => folly_compiler_flags + sqlcipher_prefix_flag,
  }

  # Security.framework provides both the SQLCipher CommonCrypto backend and the
  # Keychain APIs (SecItem*/SecRandomCopyBytes) used by ios/KeyProvider.mm to
  # store/generate SQLCipher keys. Linked unconditionally because KeyProvider.mm
  # is always compiled.
  s.frameworks = "Security"

  load 'nitrogen/generated/ios/RNNitroSQLite+autolinking.rb'
  add_nitrogen_files(s)

  install_modules_dependencies(s)

  optimizedCflags = '$(inherited) -DSQLITE_DQS=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 -DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1 -DSQLITE_MAX_EXPR_DEPTH=0 -DSQLITE_OMIT_DEPRECATED=1 -DSQLITE_OMIT_PROGRESS_CALLBACK=1 -DSQLITE_OMIT_SHARED_CACHE=1 -DSQLITE_USE_ALLOCA=1'

  if performance_mode == '1' then
    log_message.call("Thread unsafe (1) performance mode enabled. Use only transactions! 🚀🚀")
    xcconfig[:OTHER_CFLAGS] = optimizedCflags + ' -DSQLITE_THREADSAFE=0 '
  end

  if performance_mode == '2' then
    log_message.call("Thread safe (2) performance mode enabled 🚀")
    xcconfig[:OTHER_CFLAGS] = optimizedCflags + ' -DSQLITE_THREADSAFE=1 '
  end

  # cpp/**/*.{c} globs in BOTH sqlite amalgamations (cpp/sqlite + cpp/sqlcipher),
  # which would cause duplicate symbols. Always exclude the unselected one.
  # (Android does the equivalent via `list(FILTER ...)` in CMakeLists.txt.)
  excluded_files = []

  if sqlcipher_enabled then
    # SQLCipher: drop the vanilla amalgamation, keep cpp/sqlcipher. The
    # CommonCrypto backend (SQLCIPHER_CRYPTO_CC) uses Security.framework, which
    # is already linked above.
    excluded_files += ["cpp/sqlite/sqlite3.c", "cpp/sqlite/sqlite3.h"]

    if ENV['NITRO_SQLITE_USE_PHONE_VERSION'] == '1' then
      Pod::UI.warn "NITRO_SQLITE_SQLCIPHER takes precedence over NITRO_SQLITE_USE_PHONE_VERSION: the system libsqlite3 has no SQLCipher codec, so the bundled SQLCipher amalgamation is used instead."
    end
  elsif ENV['NITRO_SQLITE_USE_PHONE_VERSION'] == '1' then
    # Use the system libsqlite3 instead of any bundled amalgamation.
    excluded_files += ["cpp/sqlite/sqlite3.c", "cpp/sqlite/sqlite3.h", "cpp/sqlcipher/sqlite3.c", "cpp/sqlcipher/sqlite3.h"]
    s.library = "sqlite3"
  else
    # Default: bundled vanilla SQLite, drop the SQLCipher amalgamation.
    excluded_files += ["cpp/sqlcipher/sqlite3.c", "cpp/sqlcipher/sqlite3.h"]
  end

  s.exclude_files = excluded_files
end
