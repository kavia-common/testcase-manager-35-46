-- 001_init.sql
-- Initial schema for Robot Framework Test Management Platform
-- Idempotent: uses IF NOT EXISTS and guards

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create an app-level migration tracking table if not exists
CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    filename TEXT NOT NULL UNIQUE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- App user privileges: ensure appuser exists and has rights
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'appuser') THEN
      CREATE ROLE appuser WITH LOGIN PASSWORD 'dbuser123';
   END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO appuser;
GRANT CREATE ON SCHEMA public TO appuser;
GRANT ALL ON SCHEMA public TO appuser;

-- Core tables

-- Testcases: a single Robot test case definition
CREATE TABLE IF NOT EXISTS testcases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    content TEXT NOT NULL, -- Robot Framework test content or steps in textual form
    tags TEXT[] DEFAULT '{}',
    variables JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (name)
);

-- Groups: to logically group testcases
CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (name)
);

-- Many-to-many: group <-> testcase
CREATE TABLE IF NOT EXISTS group_testcases (
    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    testcase_id UUID NOT NULL REFERENCES testcases(id) ON DELETE CASCADE,
    position INTEGER,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, testcase_id)
);

-- Scenarios: parameterized executions built from one or many testcases
CREATE TABLE IF NOT EXISTS scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    -- optional: reference to group or single testcase
    group_id UUID REFERENCES groups(id) ON DELETE SET NULL,
    testcase_id UUID REFERENCES testcases(id) ON DELETE SET NULL,
    parameters JSONB DEFAULT '{}'::jsonb, -- key/value overrides
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (name)
);

-- Configs: key/value configuration with environment/profile support
CREATE TABLE IF NOT EXISTS configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    description TEXT,
    scope TEXT DEFAULT 'global', -- e.g., global, environment, project
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (key, scope)
);

-- Runs: high-level execution record
CREATE TABLE IF NOT EXISTS runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scenario_id UUID REFERENCES scenarios(id) ON DELETE SET NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'queued', -- queued, running, passed, failed, error, cancelled
    executor TEXT, -- user or system id
    variables JSONB DEFAULT '{}'::jsonb, -- final variables used
    tags TEXT[] DEFAULT '{}',
    note TEXT
);

-- Run steps: granular step results/log pointers
CREATE TABLE IF NOT EXISTS run_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level TEXT DEFAULT 'INFO', -- INFO, WARN, ERROR, DEBUG
    message TEXT NOT NULL,
    step_name TEXT,
    status TEXT, -- PASS/FAIL/SKIP/...
    extra JSONB DEFAULT '{}'::jsonb
);

-- Attachments: files generated during runs (e.g., logs, reports, screenshots)
CREATE TABLE IF NOT EXISTS attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID REFERENCES runs(id) ON DELETE CASCADE,
    step_id UUID REFERENCES run_steps(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    mime_type TEXT,
    storage_path TEXT NOT NULL, -- path or URL to stored artifact
    size_bytes BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Triggers for updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_testcases'
  ) THEN
    CREATE TRIGGER set_updated_at_testcases
    BEFORE UPDATE ON testcases
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_groups'
  ) THEN
    CREATE TRIGGER set_updated_at_groups
    BEFORE UPDATE ON groups
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_scenarios'
  ) THEN
    CREATE TRIGGER set_updated_at_scenarios
    BEFORE UPDATE ON scenarios
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_configs'
  ) THEN
    CREATE TRIGGER set_updated_at_configs
    BEFORE UPDATE ON configs
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
  END IF;
END
$$;

-- Basic seed data for configs (idempotent)
INSERT INTO configs (key, value, description, scope)
SELECT 'default_executor', 'system', 'Default executor name', 'global'
WHERE NOT EXISTS (SELECT 1 FROM configs WHERE key='default_executor' AND scope='global');

INSERT INTO configs (key, value, description, scope)
SELECT 'run_log_retention_days', '30', 'Retention period for run logs', 'global'
WHERE NOT EXISTS (SELECT 1 FROM configs WHERE key='run_log_retention_days' AND scope='global');

INSERT INTO configs (key, value, description, scope)
SELECT 'artifact_storage_path', '/data/artifacts', 'Base path for run artifacts', 'global'
WHERE NOT EXISTS (SELECT 1 FROM configs WHERE key='artifact_storage_path' AND scope='global');

-- Demo seed entities (safe idempotent insert-if-not-exists)
WITH ins_tc AS (
  INSERT INTO testcases (name, description, content, tags, variables)
  SELECT 'Sample Testcase', 'A demo Robot testcase', '*** Test Cases ***\nSample\n    Log    Hello World', ARRAY['sample','demo'], '{}'::jsonb
  WHERE NOT EXISTS (SELECT 1 FROM testcases WHERE name='Sample Testcase')
  RETURNING id
),
tc_id AS (
  SELECT id FROM testcases WHERE name='Sample Testcase'
  UNION ALL
  SELECT id FROM ins_tc
),
ins_grp AS (
  INSERT INTO groups (name, description, tags)
  SELECT 'Demo Group', 'A demo group of testcases', ARRAY['demo']
  WHERE NOT EXISTS (SELECT 1 FROM groups WHERE name='Demo Group')
  RETURNING id
),
grp_id AS (
  SELECT id FROM groups WHERE name='Demo Group'
  UNION ALL
  SELECT id FROM ins_grp
),
ensure_link AS (
  INSERT INTO group_testcases (group_id, testcase_id, position)
  SELECT (SELECT id FROM grp_id), (SELECT id FROM tc_id), 1
  WHERE NOT EXISTS (
    SELECT 1 FROM group_testcases WHERE group_id=(SELECT id FROM grp_id) AND testcase_id=(SELECT id FROM tc_id)
  )
  RETURNING group_id
)
INSERT INTO scenarios (name, description, group_id, parameters, tags)
SELECT 'Demo Scenario', 'Runs the demo group', (SELECT id FROM grp_id), '{"speed":"fast"}'::jsonb, ARRAY['demo','quick']
WHERE NOT EXISTS (SELECT 1 FROM scenarios WHERE name='Demo Scenario');

-- Permissions for appuser on all current tables/sequences
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO appuser;
