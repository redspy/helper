'use strict'

const { GoogleGenAI } = require('@google/genai')

let client = null

function getClient() {
  if (!client) {
    if (!process.env.GEMINI_API_KEY) throw new Error('GEMINI_API_KEY가 설정되지 않았습니다.')
    client = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY })
  }
  return client
}

const REQUIRED_SECTIONS = ['## 핵심 요약', '## 우선순위', '## 지금 바로 할 첫 행동']

function validateResponse(text) {
  if (!text || text.trim() === '') throw new Error('Gemini 응답이 비어있습니다.')
  const missing = REQUIRED_SECTIONS.filter(s => !text.includes(s))
  if (missing.length > 0) throw new Error(`Gemini 응답 형식 오류 — 누락된 섹션: ${missing.join(', ')}`)
}

async function callGemini(prompt) {
  const ai = getClient()
  const timeoutPromise = new Promise((_, reject) =>
    setTimeout(() => reject(new Error('Gemini API 타임아웃 (60초)')), 60000)
  )
  const result = await Promise.race([
    ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: prompt,
      config: {
        tools: [{ googleSearch: {} }]
      }
    }),
    timeoutPromise
  ])
  return result.text
}

async function summarize(title, content) {
  const prompt = `당신은 생산성 코치입니다. 아래 할 일을 분석해 주세요. 필요하다면 Google 검색을 통해 최신 정보를 찾아서 내용을 보완하세요.

[할 일 제목]
${title}

[원문 내용]
${content}

다음 형식으로 정리해 주세요:
## 핵심 요약
(2~3줄)

## 우선순위
상 / 중 / 하 중 하나 + 이유 한 줄

## 지금 바로 할 첫 행동
1.
2.
3.`

  let lastError

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const text = await callGemini(prompt)
      validateResponse(text)
      return text.trim()
    } catch (err) {
      lastError = err
      console.error(`[gemini] 시도 ${attempt}/3 실패: ${err.message}`)
      if (attempt < 3) await new Promise(r => setTimeout(r, 1000))
    }
  }

  throw lastError
}

module.exports = { summarize }
