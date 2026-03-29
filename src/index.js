process.env.TZ = 'Asia/Seoul'

require('dotenv').config()

const express = require('express')
const path = require('path')
const db = require('./db')
const { startScheduler } = require('./scheduler')
const tasksRouter = require('./routes/tasks')
const healthRouter = require('./routes/health')

async function main() {
  await db.initDb()

  // 서버 재시작 시 running 상태 복구
  db.prepare(`UPDATE tasks SET status='pending' WHERE status='running'`).run()

  const app = express()

  app.set('view engine', 'ejs')
  app.set('views', path.join(__dirname, 'views'))

  app.use(express.urlencoded({ extended: true }))

  app.use(healthRouter)
  app.use(tasksRouter)

  const PORT = process.env.PORT || 6240

  app.listen(PORT, () => {
    console.log(`[server] http://localhost:${PORT} 에서 실행 중`)
    startScheduler(db)
  })
}

main().catch(err => {
  console.error('[server] 시작 실패:', err)
  process.exit(1)
})
