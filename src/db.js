'use strict'

const path = require('path')
const fs = require('fs')
const initSqlJs = require('sql.js')

const dbPath = path.join(__dirname, '..', 'data', 'helper.db')
const migrationsDir = path.join(__dirname, '..', 'migrations')

let _sqlDb = null

function saveToFile() {
  const data = _sqlDb.export()
  fs.writeFileSync(dbPath, Buffer.from(data))
}

function ensureMigrationsTable() {
  _sqlDb.run(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name TEXT PRIMARY KEY,
      applied_at TEXT NOT NULL
    )
  `)
}

function isMigrationApplied(name) {
  const stmt = _sqlDb.prepare('SELECT 1 FROM schema_migrations WHERE name=? LIMIT 1')
  stmt.bind([name])
  const exists = stmt.step()
  stmt.free()
  return exists
}

function markMigrationApplied(name) {
  _sqlDb.run(
    `INSERT OR IGNORE INTO schema_migrations (name, applied_at)
     VALUES (?, datetime('now','localtime'))`,
    [name]
  )
}

function isIgnorableMigrationError(err) {
  const msg = String(err?.message || '')
  return msg.includes('duplicate column name')
}

function makeStatement(sql) {
  return {
    run(...args) {
      _sqlDb.run(sql, args.flat())
      const meta = _sqlDb.exec('SELECT changes(), last_insert_rowid()')[0]
      const [changes, lastInsertRowid] = meta ? meta.values[0] : [0, 0]
      saveToFile()
      return { changes: Number(changes), lastInsertRowid: Number(lastInsertRowid) }
    },
    get(...args) {
      const stmt = _sqlDb.prepare(sql)
      if (args.length > 0) stmt.bind(args.flat())
      const row = stmt.step() ? stmt.getAsObject() : undefined
      stmt.free()
      return row
    },
    all(...args) {
      const stmt = _sqlDb.prepare(sql)
      if (args.length > 0) stmt.bind(args.flat())
      const rows = []
      while (stmt.step()) rows.push(stmt.getAsObject())
      stmt.free()
      return rows
    }
  }
}

const wrapper = {
  prepare(sql) { return makeStatement(sql) },
  exec(sql) { _sqlDb.exec(sql); saveToFile() }
}

async function initDb() {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true })

  const SQL = await initSqlJs({
    locateFile: f => path.join(__dirname, '..', 'node_modules', 'sql.js', 'dist', f)
  })

  const fileBuffer = fs.existsSync(dbPath) ? fs.readFileSync(dbPath) : null
  _sqlDb = fileBuffer ? new SQL.Database(fileBuffer) : new SQL.Database()

  _sqlDb.run('PRAGMA foreign_keys = ON')
  ensureMigrationsTable()

  const migrationFiles = fs.readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort()

  for (const file of migrationFiles) {
    if (isMigrationApplied(file)) continue

    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8')
    try {
      _sqlDb.exec(sql)
    } catch (err) {
      if (!isIgnorableMigrationError(err)) {
        throw new Error(`[db] migration failed (${file}): ${err.message}`)
      }
      console.warn(`[db] migration already applied (${file}): ${err.message}`)
    }
    markMigrationApplied(file)
  }

  saveToFile()

  return wrapper
}

// Proxy: const db = require('./db') 기존 코드 변경 없이 동작
const proxy = new Proxy(wrapper, {
  get(target, prop) {
    if (prop === 'initDb') return initDb
    if (!_sqlDb) throw new Error('DB not initialized. Call await db.initDb() first.')
    return target[prop]
  }
})

module.exports = proxy
