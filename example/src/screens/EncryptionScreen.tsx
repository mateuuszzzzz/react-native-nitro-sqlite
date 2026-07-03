import React, { useState } from 'react'
import { ScrollView, Text, TouchableOpacity, StyleSheet } from 'react-native'
import { open } from 'react-native-nitro-sqlite'
import { ScreenStyles } from '../styles'

const DB_NAME = 'encryption-demo.sqlite'
const KEY_ID = 'encryption-demo'
const SECRET = `secret-${Date.now()}`

type Line = { text: string; ok: boolean }

/**
 * Proves the database is actually encrypted, end-to-end, using only the SQLite
 * API. The key material never passes through JS: we only supply a `keyId`, and
 * the native layer resolves/generates the real key from the platform secure
 * storage (Keychain on iOS, Keystore on Android).
 *
 *  1. Open with the keyId (generates + stores a key on first run) and write a
 *     secret.
 *  2. Reopen with the same keyId and read the secret back.
 *  3. Open with NO keyId must fail — an unencrypted DB would succeed here, so
 *     this is what proves the file is actually encrypted on disk.
 */
function runEncryptionDemo(): Line[] {
  const lines: Line[] = []
  const pass = (text: string) => lines.push({ text: `✅ ${text}`, ok: true })
  const fail = (text: string) => lines.push({ text: `❌ ${text}`, ok: false })

  // Step 1 — create/open encrypted DB via keyId and store a secret.
  try {
    const db = open({ name: DB_NAME, keyId: KEY_ID })
    db.execute('CREATE TABLE IF NOT EXISTS vault (id INTEGER PRIMARY KEY, secret TEXT)')
    db.execute('DELETE FROM vault')
    db.execute('INSERT INTO vault (secret) VALUES (?)', [SECRET])
    db.close()
    pass(`Wrote secret with keyId "${KEY_ID}": "${SECRET}"`)
  } catch (e) {
    fail(`Could not open with keyId: ${String(e)}`)
    fail('Is the native build compiled with SQLCipher support?')
    return lines
  }

  // Step 2 — reopen with the same keyId reads the secret back.
  try {
    const db = open({ name: DB_NAME, keyId: KEY_ID })
    const result = db.execute<{ secret: string }>('SELECT secret FROM vault LIMIT 1')
    const readBack = result.rows?._array?.[0]?.secret
    db.close()
    if (readBack === SECRET) {
      pass(`Read secret back with keyId: "${readBack}"`)
    } else {
      fail(`Read-back mismatch: got "${String(readBack)}"`)
    }
  } catch (e) {
    fail(`Could not read with keyId: ${String(e)}`)
  }

  // Step 3 — no keyId at all must be rejected (proves the file is encrypted).
  try {
    const db = open({ name: DB_NAME })
    db.close()
    fail('Opened with NO keyId — the file is plaintext, NOT encrypted!')
  } catch {
    pass('Opening without a keyId was rejected (file is not plaintext)')
  }

  return lines
}

export function EncryptionScreen() {
  const [lines, setLines] = useState<Line[]>([])
  const [ran, setRan] = useState(false)

  const onRun = () => {
    setLines(runEncryptionDemo())
    setRan(true)
  }

  const allOk = ran && lines.length > 0 && lines.every((l) => l.ok)

  return (
    <ScrollView contentContainerStyle={ScreenStyles.container}>
      <TouchableOpacity onPress={onRun}>
        <Text style={ScreenStyles.buttonText}>Run encryption demo</Text>
      </TouchableOpacity>

      {ran && (
        <Text style={[styles.summary, { color: allOk ? 'green' : 'crimson' }]}>
          {allOk ? 'Encryption verified' : 'Verification failed'}
        </Text>
      )}

      {lines.map((line, i) => (
        <Text key={i} style={[styles.line, { color: line.ok ? '#1a7f37' : 'crimson' }]}>
          {line.text}
        </Text>
      ))}
    </ScrollView>
  )
}

const styles = StyleSheet.create({
  summary: {
    fontSize: 18,
    fontWeight: 'bold',
    marginVertical: 12,
  },
  line: {
    fontSize: 14,
    alignSelf: 'stretch',
    marginBottom: 8,
  },
})
