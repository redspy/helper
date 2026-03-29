'use strict'

const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '..')
const dataDir = path.join(root, 'data')
const envPath = path.join(root, '.env')
const examplePath = path.join(root, '.env.example')

// 1. data/ 디렉토리 생성
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true })
  console.log('[setup] data/ 디렉토리 생성 완료')
}

// 2. .env 파일 생성 (이미 있으면 스킵)
if (!fs.existsSync(envPath)) {
  fs.copyFileSync(examplePath, envPath)
  console.log('[setup] .env 파일 생성 완료')
} else {
  console.log('[setup] .env 파일이 이미 존재합니다. 스킵.')
}

// 3. DB 초기화 (migration 자동 실행)
process.env.TZ = 'Asia/Seoul'
require('../src/db.js')
console.log('[setup] DB 초기화 완료')

console.log('\n✅ 설정 완료!')
console.log('   .env 파일에 아래 값을 입력하세요:')
console.log('   - GEMINI_API_KEY')
console.log('   - TELEGRAM_BOT_TOKEN')
console.log('   - TELEGRAM_CHAT_ID')
console.log('\n   이후 npm start 로 서버를 실행하세요.\n')
