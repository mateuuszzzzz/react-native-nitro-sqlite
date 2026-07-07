package com.margelo.rnnitrosqlite

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.SecureRandom

/**
 * Android implementation of the SQLCipher key provider.
 *
 * Key material (32 random bytes, hex-encoded) is stored in
 * [EncryptedSharedPreferences], whose master key lives in the Android Keystore
 * (hardware-backed / StrongBox when available). The raw key never crosses into
 * JavaScript: it is produced here and handed straight to sqlite3_key() by the
 * native layer.
 *
 * Called from C++ (see cpp-adapter.cpp) during `open()`. The return value is a
 * tagged string so the JNI boundary stays trivial:
 *   - "OK:<hex>"            key found or freshly generated
 *   - "UNAVAILABLE:<msg>"   no key and the db already exists (do NOT generate)
 *   - "ERROR:<msg>"         secure storage could not be accessed
 */
object KeyProvider {
  private const val KEY_BYTE_LENGTH = 32
  private const val PREFS_FILE = "com.margelo.rnnitrosqlite.keys"

  @Volatile
  private var appContext: Context? = null

  @JvmStatic
  fun setContext(context: Context) {
    appContext = context.applicationContext
  }

  private fun prefs(context: Context): SharedPreferences {
    val masterKey = MasterKey.Builder(context)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .build()
    return EncryptedSharedPreferences.create(
      context,
      PREFS_FILE,
      masterKey,
      EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
      EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
  }

  private fun toHex(bytes: ByteArray): String {
    val sb = StringBuilder(bytes.size * 2)
    for (b in bytes) {
      sb.append(Character.forDigit((b.toInt() shr 4) and 0xF, 16))
      sb.append(Character.forDigit(b.toInt() and 0xF, 16))
    }
    return sb.toString()
  }

  /** Invoked from native code. Must not throw across the JNI boundary. */
  @JvmStatic
  fun resolveKey(keyId: String, dbExists: Boolean): String {
    val context = appContext
      ?: return "ERROR:Application context is not available yet."

    return try {
      val store = prefs(context)
      val existing = store.getString(keyId, null)
      if (existing != null) {
        return "OK:$existing"
      }

      // No key stored for this keyId.
      if (dbExists) {
        // The database exists but its key is gone: do NOT generate a new one,
        // that would make the encrypted data permanently unreadable.
        return "UNAVAILABLE:the key is missing from secure storage"
      }

      val raw = ByteArray(KEY_BYTE_LENGTH)
      SecureRandom().nextBytes(raw)
      val hex = toHex(raw)
      store.edit().putString(keyId, hex).apply()
      "OK:$hex"
    } catch (e: Throwable) {
      "ERROR:${e.message ?: e.javaClass.simpleName}"
    }
  }
}
