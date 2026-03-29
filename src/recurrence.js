'use strict'

const cronParser = require('cron-parser')

function toLocalString(date) {
  return date.toLocaleString('sv-SE', { timeZone: 'Asia/Seoul' }).replace('T', ' ')
}

function nextScheduledAt(task) {
  const base = new Date(task.scheduled_at)

  switch (task.recurrence_type) {
    case 'once':
      return null

    case 'daily': {
      const next = new Date(base)
      next.setDate(next.getDate() + 1)
      return toLocalString(next)
    }

    case 'weekly': {
      const next = new Date(base)
      next.setDate(next.getDate() + 7)
      return toLocalString(next)
    }

    case 'monthly': {
      const next = new Date(base)
      // 말일 overflow (예: 1/31 → 2/28) 은 JS 기본 동작에 따름
      next.setMonth(next.getMonth() + 1)
      return toLocalString(next)
    }

    case 'custom': {
      if (!task.recurrence_rule) throw new Error('커스텀 반복 규칙이 없습니다.')
      const interval = cronParser.parseExpression(task.recurrence_rule, {
        currentDate: base,
        tz: 'Asia/Seoul',
      })
      return toLocalString(interval.next().toDate())
    }

    default:
      throw new Error(`알 수 없는 반복 유형: ${task.recurrence_type}`)
  }
}

module.exports = { nextScheduledAt }
