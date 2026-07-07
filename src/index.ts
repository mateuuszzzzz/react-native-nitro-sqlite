import { transaction } from './operations/transaction'
import { HybridNitroSQLite } from './nitro'
import { open } from './operations/session'
import { execute, executeAsync } from './operations/execute'
import { init } from './OnLoad'
import { executeBatch, executeBatchAsync } from './operations/executeBatch'

init()

export const NitroSQLite = {
  ...HybridNitroSQLite,
  native: HybridNitroSQLite,
  // Overwrite native `open` function with session-based JS abstraction,
  // where the database name can be ommited once opened
  open,
  // More JS abstractions, that perform type casting and validation.
  transaction,
  execute,
  executeAsync,
  executeBatch,
  executeBatchAsync,
}

export { open } from './operations/session'

/**
 * Checks whether a database file exists on disk without creating or opening
 * it. Useful e.g. to decide whether a legacy database still needs to be
 * migrated.
 */
export function databaseExists(dbName: string, location?: string): boolean {
  return HybridNitroSQLite.databaseExists(dbName, location)
}
export { default as NitroSQLiteError } from './NitroSQLiteError'
export type * from './types'
export { typeORMDriver } from './typeORM'
