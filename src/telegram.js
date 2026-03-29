'use strict'

const TelegramBot = require('node-telegram-bot-api')

let bot = null

function getBot() {
  if (!bot) {
    if (!process.env.TELEGRAM_BOT_TOKEN) throw new Error('TELEGRAM_BOT_TOKEN이 설정되지 않았습니다.')
    bot = new TelegramBot(process.env.TELEGRAM_BOT_TOKEN, { polling: false })
  }
  return bot
}

function buildMessage(title, scheduledAt, geminiResult, processedAt) {
  // Gemini 결과의 특수문자는 HTML 모드로 안전하게 처리
  const safeResult = geminiResult
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')

  return `<b>📋 ${title}</b>\n🕐 예정: ${scheduledAt}\n\n${safeResult}\n\n✅ 처리 시각: ${processedAt}`
}

async function sendMessage(title, scheduledAt, geminiResult, processedAt) {
  const chatId = process.env.TELEGRAM_CHAT_ID
  if (!chatId) throw new Error('TELEGRAM_CHAT_ID가 설정되지 않았습니다.')

  const text = buildMessage(title, scheduledAt, geminiResult, processedAt)
  const telegramBot = getBot()

  let lastError
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const res = await telegramBot.sendMessage(chatId, text, { parse_mode: 'HTML' })
      return String(res.message_id)
    } catch (err) {
      lastError = err
      console.error(`[telegram] 전송 실패 (${attempt}/3):`, err.message)
      if (attempt < 3) await new Promise(r => setTimeout(r, 1000))
    }
  }

  throw lastError
}

module.exports = { sendMessage }
