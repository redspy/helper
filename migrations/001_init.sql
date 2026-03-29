CREATE TABLE IF NOT EXISTS tasks (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  title           TEXT    NOT NULL,
  content         TEXT    NOT NULL,
  scheduled_at    TEXT    NOT NULL,
  recurrence_type TEXT    NOT NULL DEFAULT 'once',
  recurrence_rule TEXT,
  status          TEXT    NOT NULL DEFAULT 'pending',
  last_run_at     TEXT,
  archived_at     TEXT,
  created_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
  updated_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime'))
);

CREATE TABLE IF NOT EXISTS task_runs (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id             INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  trace_id            TEXT    NOT NULL,
  started_at          TEXT    NOT NULL,
  finished_at         TEXT,
  status              TEXT    NOT NULL,
  gemini_result       TEXT,
  telegram_message_id TEXT,
  error_message       TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_status_scheduled
  ON tasks(status, scheduled_at);
