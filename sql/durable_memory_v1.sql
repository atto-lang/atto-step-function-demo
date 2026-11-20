-- PostgreSQL v1 schema sketch for a future Oreslang durable memory adapter.
-- NOT executed or integrated with the host-only demo. Requires migration review,
-- RLS/roles, authenticated CI ingress, database tests and transaction implementation.

BEGIN;

CREATE TABLE IF NOT EXISTS workflow_runs (
  tenant_id text NOT NULL,
  workflow_id text NOT NULL,
  run_id text NOT NULL,
  definition_version integer NOT NULL CHECK (definition_version > 0),
  activation_epoch bigint NOT NULL DEFAULT 0 CHECK (activation_epoch >= 0),
  state_version bigint NOT NULL DEFAULT 0 CHECK (state_version >= 0),
  status text NOT NULL CHECK
    (status IN ('RUNNING','WAITING','FAILED','CANCELLED','COMPLETED')),
  last_checkpoint_hash text,
  PRIMARY KEY (tenant_id, workflow_id, run_id)
);

CREATE TABLE IF NOT EXISTS verified_ci_runs (
  tenant_id text NOT NULL,
  repository_full_name text NOT NULL,
  run_id bigint NOT NULL CHECK (run_id > 0),
  run_attempt integer NOT NULL CHECK (run_attempt > 0),
  source_sha text NOT NULL CHECK
    (source_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  workflow_name text NOT NULL,
  executed_steps integer NOT NULL CHECK (executed_steps > 0),
  verified_at timestamptz NOT NULL,
  verification_expires_at timestamptz,
  trusted_verifier_id text NOT NULL,
  PRIMARY KEY (tenant_id, repository_full_name, run_id, run_attempt),
  CHECK (verification_expires_at IS NULL OR
         verification_expires_at > verified_at)
);

CREATE TABLE IF NOT EXISTS memory_records (
  tenant_id text NOT NULL,
  event_id text NOT NULL,
  repository_full_name text NOT NULL,
  source_sha text NOT NULL CHECK
    (source_sha ~ '^[0-9a-f]{40}([0-9a-f]{24})?$'),
  ci_run_id bigint NOT NULL,
  ci_run_attempt integer NOT NULL,
  content jsonb NOT NULL DEFAULT '{}'::jsonb,
  indexed boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,event_id),
  FOREIGN KEY (tenant_id,repository_full_name,ci_run_id,ci_run_attempt)
    REFERENCES verified_ci_runs(tenant_id,repository_full_name,run_id,run_attempt)
);

CREATE TABLE IF NOT EXISTS workflow_inbox (
  tenant_id text NOT NULL,
  workflow_id text NOT NULL,
  run_id text NOT NULL,
  delivery_id text NOT NULL,
  admitted_at timestamptz NOT NULL DEFAULT now(),
  consumed_version bigint,
  PRIMARY KEY (tenant_id,workflow_id,run_id,delivery_id),
  FOREIGN KEY (tenant_id,workflow_id,run_id)
    REFERENCES workflow_runs(tenant_id,workflow_id,run_id)
);

CREATE TABLE IF NOT EXISTS workflow_outbox (
  tenant_id text NOT NULL,
  workflow_id text NOT NULL,
  run_id text NOT NULL,
  intent_id text NOT NULL,
  created_version bigint NOT NULL CHECK(created_version >= 0),
  intent_kind text NOT NULL,
  state text NOT NULL DEFAULT 'PENDING' CHECK
    (state IN ('PENDING','ADMITTED','CONFIRMED','FAILED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,workflow_id,run_id,intent_id),
  FOREIGN KEY (tenant_id,workflow_id,run_id)
    REFERENCES workflow_runs(tenant_id,workflow_id,run_id)
);

CREATE INDEX IF NOT EXISTS memory_records_active_lookup
  ON memory_records(tenant_id,repository_full_name,created_at DESC)
  WHERE indexed AND deleted_at IS NULL;

COMMIT;

-- Example fenced transition, run in a single SERIALIZABLE transaction after
-- authenticating caller and per-tenant authorization:
--
-- BEGIN ISOLATION LEVEL SERIALIZABLE;
-- UPDATE workflow_runs
-- SET state_version = state_version+1
-- WHERE tenant_id=:tenant AND workflow_id=:workflow AND run_id=:run
--   AND activation_epoch=:expected_epoch
--   AND state_version=:expected_version
-- RETURNING state_version;
-- -- REQUIRE exactly one returned row; otherwise ROLLBACK (stale activation).
-- INSERT INTO workflow_inbox(...) ... ON CONFLICT DO NOTHING;
-- -- REQUIRE delivery was newly claimed before applying state/outbox intents.
-- INSERT INTO memory_records(...) ...;
-- INSERT INTO workflow_outbox(...) ...;
-- COMMIT;
--
-- A transaction that combines the inbox claim and fenced state update must
-- rollback both on replay or stale epoch. Dispatch network effects only after
-- commit, with idempotent reconciliation. This SQL is not executable proof of
-- those rules. Database roles and row-level security must enforce tenant access;
-- a tenant_id WHERE clause in application code alone is insufficient.
