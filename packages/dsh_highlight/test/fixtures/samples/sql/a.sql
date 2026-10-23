-- Create and query
CREATE TABLE IF NOT EXISTS users (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        VARCHAR(100) NOT NULL,
    email       TEXT UNIQUE,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

/* multi-line
   comment */
INSERT INTO users (name, email) VALUES ('O''Brien', 'ob@example.org');

SELECT u.id, COUNT(*) AS total, MAX(o.amount) AS biggest
FROM users u
INNER JOIN orders o ON o.user_id = u.id
WHERE u.name LIKE 'A%' AND o.amount BETWEEN 10 AND 20.5
  AND u.id IN (1, 2, 3) OR u.email IS NOT NULL
GROUP BY u.id
HAVING COUNT(*) > 1
ORDER BY total DESC, u.name ASC
LIMIT 10 OFFSET 5;

UPDATE users SET name = "double" WHERE id = 1;
DELETE FROM users WHERE created_at < '2020-01-01';
