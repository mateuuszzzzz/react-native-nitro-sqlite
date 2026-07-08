"use strict";

import { transaction } from "./operations/transaction.js";
import { HybridNitroSQLite } from "./nitro.js";
import { open } from "./operations/session.js";
import { execute, executeAsync } from "./operations/execute.js";
import { init } from './OnLoad';
import { executeBatch, executeBatchAsync } from "./operations/executeBatch.js";
init();
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
  executeBatchAsync
};
export { open } from "./operations/session.js";

/**
 * Checks whether a database file exists on disk without creating or opening
 * it. Useful e.g. to decide whether a legacy database still needs to be
 * migrated.
 */
export function databaseExists(dbName, location) {
  return HybridNitroSQLite.databaseExists(dbName, location);
}
export { default as NitroSQLiteError } from "./NitroSQLiteError.js";
export { typeORMDriver } from "./typeORM.js";
//# sourceMappingURL=index.js.map