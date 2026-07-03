#include <fbjni/fbjni.h>
#include <jni.h>
#include <jsi/jsi.h>
#include <typeinfo>
#include "HybridNitroSQLite.hpp"
#include "KeyProvider.hpp"
#include "RNNitroSQLiteOnLoad.hpp"

using namespace margelo::nitro::rnnitrosqlite;
using namespace margelo::rnnitrosqlite;

namespace {

JavaVM* g_javaVM = nullptr;

// Attaches the current thread to the JVM if needed and returns a JNIEnv. When
// `didAttach` is set true, the caller must detach before returning.
JNIEnv* getJNIEnv(bool& didAttach) {
  didAttach = false;
  if (g_javaVM == nullptr) {
    return nullptr;
  }
  JNIEnv* env = nullptr;
  jint result = g_javaVM->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
  if (result == JNI_EDETACHED) {
    if (g_javaVM->AttachCurrentThread(&env, nullptr) == JNI_OK) {
      didAttach = true;
    } else {
      return nullptr;
    }
  } else if (result != JNI_OK) {
    return nullptr;
  }
  return env;
}

// Parses the tagged string returned by Kotlin KeyProvider.resolveKey into a
// KeyResolveResult ("OK:<hex>" / "UNAVAILABLE:<msg>" / "ERROR:<msg>").
KeyResolveResult parseResolveResult(const std::string& tagged) {
  const auto colon = tagged.find(':');
  const std::string tag = colon == std::string::npos ? tagged : tagged.substr(0, colon);
  const std::string rest = colon == std::string::npos ? "" : tagged.substr(colon + 1);

  if (tag == "OK") {
    return KeyResolveResult::ok(rest);
  }
  if (tag == "UNAVAILABLE") {
    return KeyResolveResult::unavailable(rest);
  }
  return KeyResolveResult::error(rest.empty() ? "Unknown secure key store error" : rest);
}

KeyResolveResult resolveKeyViaJNI(const std::string& keyId, bool dbExists) {
  bool didAttach = false;
  JNIEnv* env = getJNIEnv(didAttach);
  if (env == nullptr) {
    return KeyResolveResult::error("Could not attach to the JVM to resolve the encryption key.");
  }

  KeyResolveResult result = KeyResolveResult::error("Secure key store call failed.");

  jclass clazz = env->FindClass("com/margelo/rnnitrosqlite/KeyProvider");
  if (clazz != nullptr) {
    jmethodID method =
        env->GetStaticMethodID(clazz, "resolveKey", "(Ljava/lang/String;Z)Ljava/lang/String;");
    if (method != nullptr) {
      jstring jKeyId = env->NewStringUTF(keyId.c_str());
      jstring jResult = static_cast<jstring>(
          env->CallStaticObjectMethod(clazz, method, jKeyId, static_cast<jboolean>(dbExists)));

      if (env->ExceptionCheck()) {
        env->ExceptionClear();
        result = KeyResolveResult::error("Secure key store threw an exception.");
      } else if (jResult != nullptr) {
        const char* chars = env->GetStringUTFChars(jResult, nullptr);
        result = parseResolveResult(std::string(chars));
        env->ReleaseStringUTFChars(jResult, chars);
      }

      if (jResult != nullptr) {
        env->DeleteLocalRef(jResult);
      }
      env->DeleteLocalRef(jKeyId);
    }
    env->DeleteLocalRef(clazz);
  } else {
    env->ExceptionClear();
    result = KeyResolveResult::error("KeyProvider class not found.");
  }

  if (didAttach) {
    g_javaVM->DetachCurrentThread();
  }
  return result;
}

} // namespace

namespace margelo::rnnitrosqlite {
// Called directly from sqliteOpenDb (C++); resolved by the linker at build
// time. Delegates to Kotlin KeyProvider via JNI (g_javaVM is cached in
// JNI_OnLoad, which always runs before any JS call can reach open()).
KeyResolveResult resolvePlatformEncryptionKey(const std::string& keyId, bool dbExists) {
  return resolveKeyViaJNI(keyId, dbExists);
}
} // namespace margelo::rnnitrosqlite

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    g_javaVM = vm;
    return margelo::nitro::rnnitrosqlite::initialize(vm);
}

extern "C"
JNIEXPORT void JNICALL
Java_com_margelo_rnnitrosqlite_DocPathSetter_setDocPathInJNI(JNIEnv *env, jclass clazz,
                                                                         jstring doc_path) {
  const char *nativeString = env->GetStringUTFChars(doc_path, nullptr);
  HybridNitroSQLite::docPath = std::string(nativeString);
  env->ReleaseStringUTFChars(doc_path, nativeString);
}
