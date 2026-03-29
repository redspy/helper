'use strict'

const cron = require('node-cron')
const { randomUUID } = require('crypto')
const { summarize } = require('./gemini')
const { sendMessage } = require('./telegram')
const { nextScheduledAt } = require('./recurrence')

function nowLocal() {
  return new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Seoul' }).replace('T', ' ')
}

async function processTask(task, db) {
  // status='running'으로 전환 (중복 실행 방지)
  const locked = db.prepare(`
    UPDATE tasks SET status='running', updated_at=? WHERE id=? AND status='pending'
  `).run(nowLocal(), task.id)

  if (locked.changes === 0) {
    console.log(`[scheduler] task ${task.id} 이미 처리 중 — 스킵`)
    return
  }

  const traceId = randomUUID()
  const startedAt = nowLocal()

  const runId = db.prepare(`
    INSERT INTO task_runs (task_id, trace_id, started_at, status)
    VALUES (?, ?, ?, 'running')
  `).run(task.id, traceId, startedAt).lastInsertRowid

  console.log(`[${traceId}] task ${task.id} "${task.title}" 처리 시작`)

  try {
    const geminiResult = await summarize(task.title, task.content)
    const processedAt = nowLocal()
    const messageId = await sendMessage(task.title, task.scheduled_at, geminiResult, processedAt)

    const finishedAt = nowLocal()

    db.prepare(`
      UPDATE task_runs
      SET finished_at=?, status='success', gemini_result=?, telegram_message_id=?
      WHERE id=?
    `).run(finishedAt, geminiResult, messageId, runId)

    if (task.recurrence_type === 'once') {
      db.prepare(`
        UPDATE tasks SET status='archived', archived_at=?, last_run_at=?, updated_at=? WHERE id=?
      `).run(finishedAt, finishedAt, finishedAt, task.id)
    } else {
      const nextAt = nextScheduledAt(task)
      db.prepare(`
        UPDATE tasks SET status='pending', scheduled_at=?, last_run_at=?, updated_at=? WHERE id=?
      `).run(nextAt, finishedAt, finishedAt, task.id)
    }

    console.log(`[${traceId}] task ${task.id} 처리 완료`)
  } catch (err) {
    const finishedAt = nowLocal()
    console.error(`[${traceId}] task ${task.id} 처리 실패:`, err.message)

    db.prepare(`
      UPDATE task_runs SET finished_at=?, status='failed', error_message=? WHERE id=?
    `).run(finishedAt, err.message, runId)

    db.prepare(`
      UPDATE tasks SET status='failed', last_run_at=?, updated_at=? WHERE id=?
    `).run(finishedAt, finishedAt, task.id)
  }
}

function startScheduler(db) {
  cron.schedule('* * * * *', async () => {
    const due = db.prepare(`
      SELECT * FROM tasks
      WHERE status='pending' AND scheduled_at <= datetime('now','localtime')
    `).all()

    if (due.length > 0) {
      console.log(`[scheduler] 처리 대상 ${due.length}건`)
    }

    for (const task of due) {
      await processTask(task, db)
    }
  }, { timezone: 'Asia/Seoul' })

  console.log('[scheduler] 시작 (1분 폴링)')
}

module.exports = { startScheduler, processTask }
