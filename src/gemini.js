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

function validateResponse(text) {
  if (!text || text.trim() === '') throw new Error('Gemini 응답이 비어있습니다.')
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
  const prompt = `당신은 유능한 AI 어시스턴트입니다. 아래 할 일 또는 주제에 대해 분석하고, 필요하다면 Google 검색을 통해 최신 정보를 찾아서 도움이 되는 내용을 자유롭게 응답해 주세요.

응답 시 마크다운 문법(*, **, #, -, ``` 등)을 사용하지 말고, 일반 텍스트로만 작성해 주세요.

[제목]
${title}

[내용]
${content}`

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
