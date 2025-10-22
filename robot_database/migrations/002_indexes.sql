-- 002_indexes.sql
-- Indexes to optimize queries

-- Idempotent GIN indexes for array/jsonb fields
CREATE INDEX IF NOT EXISTS idx_testcases_tags_gin ON testcases USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_testcases_variables_gin ON testcases USING GIN (variables);

CREATE INDEX IF NOT EXISTS idx_groups_tags_gin ON groups USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_scenarios_tags_gin ON scenarios USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_scenarios_parameters_gin ON scenarios USING GIN (parameters);

CREATE INDEX IF NOT EXISTS idx_runs_status ON runs (status);
CREATE INDEX IF NOT EXISTS idx_runs_started_at ON runs (started_at);
CREATE INDEX IF NOT EXISTS idx_runs_finished_at ON runs (finished_at);
CREATE INDEX IF NOT EXISTS idx_runs_tags_gin ON runs USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_runs_variables_gin ON runs USING GIN (variables);

-- Run steps by run_id + ts to support chronological step queries
CREATE INDEX IF NOT EXISTS idx_run_steps_runid_ts ON run_steps (run_id, ts);

-- Attachments by run and step for quick lookups
CREATE INDEX IF NOT EXISTS idx_attachments_runid ON attachments (run_id);
CREATE INDEX IF NOT EXISTS idx_attachments_stepid ON attachments (step_id);
