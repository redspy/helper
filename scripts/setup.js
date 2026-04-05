'use strict'

const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '..')
const dataDir = path.join(root, 'data')
const envPath = path.join(root, '.env')
const examplePath = path.join(root, '.env.example')

async function main() {
  // 1. data/ 디렉토리 생성
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true })
    console.log('[setup] data/ 디렉토리 생성 완료')
  }

  // 2. .env 파일 생성 (기존 파일은 유지)
  if (!fs.existsSync(envPath)) {
    fs.copyFileSync(examplePath, envPath)
    console.log('[setup] .env 파일 생성 완료')
  } else {
    console.log('[setup] .env 파일이 이미 존재하여 유지합니다')
  }

  // 3. DB 초기화 (migration 자동 실행)
  process.env.TZ = 'Asia/Seoul'
  const db = require('../src/db.js')
  await db.initDb()
  console.log('[setup] DB 초기화 완료')

  console.log('\n✅ 설정 완료!')
  console.log('   .env 파일에 아래 값을 입력하세요:')
  console.log('   - GEMINI_API_KEY')
  console.log('   - TELEGRAM_BOT_TOKEN')
  console.log('   - TELEGRAM_CHAT_ID')
  console.log('\n   이후 npm start 로 서버를 실행하세요.\n')
}

main().catch(err => {
  console.error('[setup] 실패:', err)
  process.exit(1)
})
