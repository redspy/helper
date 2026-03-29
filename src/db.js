'use strict'

const path = require('path')
const fs = require('fs')
const Database = require('better-sqlite3')

const dbPath = path.join(__dirname, '..', 'data', 'helper.db')
const migrationPath = path.join(__dirname, '..', 'migrations', '001_init.sql')

const db = new Database(dbPath)

db.pragma('journal_mode = WAL')
db.pragma('foreign_keys = ON')

const sql = fs.readFileSync(migrationPath, 'utf8')
db.exec(sql)

module.exports = db
