'use strict'

const { GoogleGenerativeAI } = require('@google/generative-ai')

let client = null

function getModel() {
  if (!client) {
    if (!process.env.GEMINI_API_KEY) throw new Error('GEMINI_API_KEY가 설정되지 않았습니다.')
    client = new GoogleGenerativeAI(process.env.GEMINI_API_KEY)
  }
  return client.getGenerativeModel({ model: 'gemini-1.5-flash' })
}

async function summarize(title, content) {
  const prompt = `당신은 생산성 코치입니다. 아래 할 일을 분석해 주세요.

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

  const model = getModel()

  const resultPromise = model.generateContent(prompt)
  const timeoutPromise = new Promise((_, reject) =>
    setTimeout(() => reject(new Error('Gemini API 타임아웃 (30초)')), 30000)
  )

  const result = await Promise.race([resultPromise, timeoutPromise])
  const text = result.response.text()

  if (!text || text.trim() === '') throw new Error('Gemini 응답이 비어있습니다.')

  return text.trim()
}

module.exports = { summarize }
