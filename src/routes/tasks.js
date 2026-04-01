'use strict'

const express = require('express')
const router = express.Router()
const db = require('../db')
const { processTask } = require('../scheduler')

function nowLocal() {
  return new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Seoul' }).replace('T', ' ')
}

// datetime-local 입력값 정규화: "2026-04-01T14:30" → "2026-04-01 14:30:00"
function normalizeScheduledAt(value) {
  return value.replace('T', ' ') + (value.length === 16 ? ':00' : '')
}

const ACTIVE_STATUSES = `'pending','running','sent','failed'`

// 활성 task + 마지막 실행 결과 조회
function getActiveTasks() {
  return db.prepare(`
    SELECT t.*,
           r.gemini_result     AS last_gemini_result,
           r.error_message     AS last_error,
           r.status            AS last_run_status
    FROM tasks t
    LEFT JOIN task_runs r ON r.id = (
      SELECT id FROM task_runs WHERE task_id = t.id ORDER BY started_at DESC LIMIT 1
    )
    WHERE t.status IN (${ACTIVE_STATUSES})
    ORDER BY t.scheduled_at ASC
  `).all()
}

function getArchivedTasks() {
  return db.prepare(`
    SELECT * FROM tasks WHERE status='archived' ORDER BY archived_at DESC
  `).all()
}

// GET /
router.get('/', (req, res) => {
  const tasks = getActiveTasks()
  const archived = getArchivedTasks()
  res.render('index', { tasks, archived, error: null })
})

// POST /tasks — 등록
router.post('/tasks', (req, res) => {
  const { title, content, scheduled_at, recurrence_type, recurrence_rule } = req.body

  if (!title || !content || !scheduled_at || !recurrence_type) {
    const tasks = getActiveTasks()
    const archived = getArchivedTasks()
    return res.render('index', { tasks, archived, error: '필수 항목을 모두 입력해주세요.' })
  }

  const now = nowLocal()
  db.prepare(`
    INSERT INTO tasks (title, content, scheduled_at, recurrence_type, recurrence_rule, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(
    title.trim(),
    content.trim(),
    normalizeScheduledAt(scheduled_at),
    recurrence_type,
    recurrence_type === 'custom' ? (recurrence_rule || null) : null,
    now,
    now
  )

  res.redirect('/')
})

// POST /tasks/:id/update — 수정
router.post('/tasks/:id/update', (req, res) => {
  const { title, content, scheduled_at, recurrence_type, recurrence_rule } = req.body
  const { id } = req.params

  if (!title || !content || !scheduled_at || !recurrence_type) {
    return res.redirect('/')
  }

  db.prepare(`
    UPDATE tasks
    SET title=?, content=?, scheduled_at=?, recurrence_type=?, recurrence_rule=?, updated_at=?
    WHERE id=? AND status != 'archived'
  `).run(
    title.trim(),
    content.trim(),
    normalizeScheduledAt(scheduled_at),
    recurrence_type,
    recurrence_type === 'custom' ? (recurrence_rule || null) : null,
    nowLocal(),
    id
  )

  res.redirect('/')
})

// POST /tasks/:id/delete — 삭제
router.post('/tasks/:id/delete', (req, res) => {
  db.prepare('DELETE FROM tasks WHERE id=?').run(req.params.id)
  res.redirect('/')
})

// POST /tasks/:id/run — 수동 실행
router.post('/tasks/:id/run', async (req, res) => {
  const task = db.prepare('SELECT * FROM tasks WHERE id=?').get(req.params.id)
  if (!task) return res.redirect('/')

  // failed/sent 상태도 수동 실행 가능하도록 pending으로 리셋
  if (task.status !== 'pending' && task.status !== 'running') {
    db.prepare(`UPDATE tasks SET status='pending', updated_at=? WHERE id=?`)
      .run(nowLocal(), task.id)
    task.status = 'pending'
  }

  await processTask(task, db)
  res.redirect('/')
})

// GET /tasks?view=archived — 지난 할 일 목록 조회 (JSON)
router.get('/tasks', (req, res) => {
  if (req.query.view === 'archived') {
    return res.json(getArchivedTasks())
  }
  res.json(getActiveTasks())
})

// POST /tasks/:id/reschedule — 지난 할 일 재활성화
router.post('/tasks/:id/reschedule', (req, res) => {
  const { scheduled_at } = req.body
  if (!scheduled_at) return res.redirect('/')

  db.prepare(`
    UPDATE tasks
    SET status='pending', scheduled_at=?, archived_at=NULL, updated_at=?
    WHERE id=? AND status='archived'
  `).run(normalizeScheduledAt(scheduled_at), nowLocal(), req.params.id)

  res.redirect('/')
})

module.exports = router
