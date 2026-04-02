INSERT INTO tasks (title, content, scheduled_at, recurrence_type, recurrence_rule, status, created_at, updated_at)
SELECT
  '점심 대화 주제 추천',
  '오늘 기준으로 IT, AI, 게임, 개발 문화 관련 최신 뉴스를 검색해서 젊은 개발자들이 흥미로워할 만한 대화 주제 5가지를 추천해줘. 각 주제마다 왜 재미있는지 한 줄 설명도 붙여줘. 딱딱하지 않고 점심 식사 자리에서 가볍게 꺼낼 수 있는 톤으로 정리해줘.',
  '2026-04-03 11:30:00',
  'daily',
  NULL,
  'pending',
  datetime('now', 'localtime'),
  datetime('now', 'localtime')
WHERE NOT EXISTS (
  SELECT 1 FROM tasks WHERE title = '점심 대화 주제 추천'
);
