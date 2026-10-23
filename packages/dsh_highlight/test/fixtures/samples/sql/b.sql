WITH RECURSIVE tree(id, parent, depth) AS (
    SELECT id, parent_id, 0 FROM nodes WHERE parent_id IS NULL
    UNION ALL
    SELECT n.id, n.parent_id, t.depth + 1
    FROM nodes AS n JOIN tree t ON n.parent_id = t.id
)
SELECT DISTINCT t.*, CASE WHEN depth > 2 THEN 'deep' ELSE 'shallow' END AS kind,
       COALESCE(NULLIF(name, ''), 'n/a') AS label, CAST(id AS VARCHAR(10)) AS sid,
       ROW_NUMBER() OVER (PARTITION BY parent ORDER BY id) AS rn
FROM tree t LEFT OUTER JOIN meta m USING (id)
WHERE name NOT LIKE '%x\%%' ESCAPE '\' AND created > DATE '2020-01-01' AND (a = 1 OR b <> 2 OR c >= 3.5e1)
  AND EXISTS (SELECT 1 FROM other o WHERE o.id = t.id) AND d IN ('a', "b") -- comment
ORDER BY 1 DESC NULLS LAST;

CREATE UNIQUE INDEX idx_nodes ON nodes (parent_id, name);
ALTER TABLE nodes ADD COLUMN flag BOOLEAN DEFAULT TRUE NOT NULL, ADD CONSTRAINT fk FOREIGN KEY (parent_id) REFERENCES nodes(id) ON DELETE CASCADE;
CREATE OR REPLACE VIEW v AS SELECT 1;
DROP TABLE IF EXISTS tmp;
BEGIN; INSERT INTO t(a, b) VALUES (1, 'it''s'), (2, NULL); COMMIT;
GRANT SELECT ON nodes TO reader;
