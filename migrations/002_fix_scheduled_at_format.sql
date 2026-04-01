-- T 구분자를 공백으로, 초가 없으면 :00 추가
-- "2026-04-01T14:30" → "2026-04-01 14:30:00"
UPDATE tasks
SET scheduled_at = REPLACE(scheduled_at, 'T', ' ') || ':00'
WHERE scheduled_at LIKE '%T%' AND length(scheduled_at) = 16;

UPDATE tasks
SET scheduled_at = REPLACE(scheduled_at, 'T', ' ')
WHERE scheduled_at LIKE '%T%' AND length(scheduled_at) > 16;
