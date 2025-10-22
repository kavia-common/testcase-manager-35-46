-- startup.sql
-- This file contains seed/default configuration applied at startup (idempotent)

-- Default global configurations (if not already present)
INSERT INTO configs (key, value, description, scope)
SELECT 'max_parallel_runs', '3', 'Max number of concurrent runs', 'global'
WHERE NOT EXISTS (SELECT 1 FROM configs WHERE key='max_parallel_runs' AND scope='global');

INSERT INTO configs (key, value, description, scope)
SELECT 'default_timeout_seconds', '300', 'Default timeout for a testcase', 'global'
WHERE NOT EXISTS (SELECT 1 FROM configs WHERE key='default_timeout_seconds' AND scope='global');

-- Ensure demo scenario exists (useful for first run environments)
INSERT INTO scenarios (name, description, parameters, tags)
SELECT 'Quickstart Scenario', 'One-click example scenario', '{"example":"true"}'::jsonb, ARRAY['quickstart','example']
WHERE NOT EXISTS (SELECT 1 FROM scenarios WHERE name='Quickstart Scenario');
