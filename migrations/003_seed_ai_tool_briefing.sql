INSERT INTO tasks (title, content, scheduled_at, recurrence_type, recurrence_rule, status, created_at, updated_at)
SELECT
  'AI 도구 업데이트',
  '개발자 생산성을 높일 수 있는 최신 AI 코딩 도구, IDE 플러그인, 자동화 툴 소식을 검색해서 정리해줘',
  '2026-04-09 09:50:00',
  'weekly',
  NULL,
  'pending',
  datetime('now', 'localtime'),
  datetime('now', 'localtime')
WHERE NOT EXISTS (
  SELECT 1 FROM tasks WHERE title = 'AI 도구 업데이트'
);
