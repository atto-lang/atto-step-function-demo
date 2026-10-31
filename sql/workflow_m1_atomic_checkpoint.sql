-- RESTRICTED M1 PostgreSQL storage prototype. No guest adapter is wired.
-- Requires a separately authenticated tenant-capability ingress and an
-- awaited COMMIT (synchronous_commit=on) before acknowledging any workflow.
BEGIN;
CREATE SCHEMA IF NOT EXISTS workflow_m1;
REVOKE ALL ON SCHEMA workflow_m1 FROM PUBLIC;
CREATE TABLE IF NOT EXISTS workflow_m1.runs (
 tenant text NOT NULL, namespace text NOT NULL, workflow text NOT NULL,
 run text NOT NULL, generation bigint NOT NULL CHECK(generation>0),
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 event_seq bigint NOT NULL DEFAULT 0 CHECK(event_seq>=0),
 phase text NOT NULL CHECK(length(phase) BETWEEN 1 AND 64),
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
 snapshot_digest text NOT NULL CHECK(snapshot_digest ~ '^sha256:[0-9a-f]{64}$'),
 quarantined boolean NOT NULL DEFAULT false,
 PRIMARY KEY(tenant,namespace,workflow,run)
);
CREATE TABLE IF NOT EXISTS workflow_m1.inbox (
 tenant text NOT NULL, namespace text NOT NULL, workflow text NOT NULL,
 run text NOT NULL, delivery text NOT NULL CHECK(length(delivery) BETWEEN 1 AND 128),
 applied_version bigint NOT NULL CHECK(applied_version>0),
 PRIMARY KEY(tenant,namespace,workflow,run,delivery),
 FOREIGN KEY(tenant,namespace,workflow,run)
 REFERENCES workflow_m1.runs(tenant,namespace,workflow,run)
);
CREATE TABLE IF NOT EXISTS workflow_m1.events (
 tenant text NOT NULL, namespace text NOT NULL, workflow text NOT NULL,
 run text NOT NULL, seq bigint NOT NULL CHECK(seq>0),
 event_id text NOT NULL CHECK(length(event_id) BETWEEN 1 AND 128),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'),
 PRIMARY KEY(tenant,namespace,workflow,run,seq),
 UNIQUE(tenant,namespace,workflow,run,event_id),
 FOREIGN KEY(tenant,namespace,workflow,run)
 REFERENCES workflow_m1.runs(tenant,namespace,workflow,run)
);
CREATE TABLE IF NOT EXISTS workflow_m1.outbox (
 tenant text NOT NULL, namespace text NOT NULL, workflow text NOT NULL,
 run text NOT NULL, effect_key text NOT NULL
 CHECK(length(effect_key) BETWEEN 1 AND 128),
 version bigint NOT NULL CHECK(version>0),
 status text NOT NULL DEFAULT 'PREPARED'
 CHECK(status IN ('PREPARED','IN_FLIGHT','UNKNOWN','CONFIRMED','FAILED')),
 PRIMARY KEY(tenant,namespace,workflow,run,effect_key),
 FOREIGN KEY(tenant,namespace,workflow,run)
 REFERENCES workflow_m1.runs(tenant,namespace,workflow,run)
);
CREATE TABLE IF NOT EXISTS workflow_m1.timers (
 tenant text NOT NULL, namespace text NOT NULL, workflow text NOT NULL,
 run text NOT NULL, timer_key text NOT NULL
 CHECK(length(timer_key) BETWEEN 1 AND 128),
 version bigint NOT NULL CHECK(version>0),
 due_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'ARMED'
 CHECK(status IN ('ARMED','FIRED','CANCELLED')),
 PRIMARY KEY(tenant,namespace,workflow,run,timer_key),
 FOREIGN KEY(tenant,namespace,workflow,run)
 REFERENCES workflow_m1.runs(tenant,namespace,workflow,run)
);
REVOKE ALL ON ALL TABLES IN SCHEMA workflow_m1 FROM PUBLIC;

-- Atomic inbox + snapshot/version + event + optional outbox/timer intent.
-- SERIALIZATION: run row lock serializes concurrent operations on the run.
-- Adapter calls this inside BEGIN with synchronous_commit=on, awaits COMMIT,
-- and ONLY THEN sends an acknowledgement. APPLIED is not a durable ACK.
-- Strictly no guest privileges or direct table writes. An authenticated
-- runtime must authorize tenant, run, and generation before invoking.
CREATE OR REPLACE FUNCTION workflow_m1.apply_checkpoint(
 p_tenant text,p_namespace text,p_workflow text,p_run text,
 p_generation bigint,p_version bigint,p_seq bigint,
 p_delivery text,p_event text,p_phase text,
 p_snapshot jsonb,p_digest text,p_payload jsonb,
 p_effect text DEFAULT NULL,p_timer text DEFAULT NULL,
 p_due timestamptz DEFAULT NULL
) RETURNS TABLE(result_code text,result_version bigint)
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,workflow_m1 AS $$
DECLARE r workflow_m1.runs%ROWTYPE;
BEGIN
 IF p_generation IS NULL OR p_generation<=0
 OR p_version IS NULL OR p_version<0 OR p_version=9223372036854775807
 OR p_seq IS NULL OR p_seq<0 OR p_seq=9223372036854775807
 OR NOT coalesce(length(p_delivery) BETWEEN 1 AND 128,false)
 OR NOT coalesce(length(p_event) BETWEEN 1 AND 128,false)
 OR NOT coalesce(length(p_phase) BETWEEN 1 AND 64,false)
 OR NOT coalesce(jsonb_typeof(p_snapshot)='object',false)
 OR NOT coalesce(jsonb_typeof(p_payload)='object',false)
 OR NOT coalesce(p_digest ~ '^sha256:[0-9a-f]{64}$',false)
 OR (p_effect IS NOT NULL AND length(p_effect) NOT BETWEEN 1 AND 128)
 OR (p_timer IS NULL AND p_due IS NOT NULL)
 OR (p_timer IS NOT NULL AND
     (length(p_timer) NOT BETWEEN 1 AND 128 OR p_due IS NULL)) THEN
   RAISE EXCEPTION 'invalid checkpoint request' USING ERRCODE='22023';
 END IF;
 SELECT * INTO r FROM workflow_m1.runs
 WHERE tenant=p_tenant AND namespace=p_namespace
 AND workflow=p_workflow AND run=p_run FOR UPDATE;
 IF NOT FOUND THEN RETURN QUERY SELECT 'MISSING'::text,NULL::bigint; RETURN; END IF;
 IF r.quarantined THEN
   RETURN QUERY SELECT 'QUARANTINED'::text,r.version; RETURN;
 END IF;
 IF r.generation<>p_generation THEN
   RETURN QUERY SELECT 'FENCED'::text,r.version; RETURN;
 END IF;
 IF EXISTS(SELECT 1 FROM workflow_m1.inbox i
   WHERE i.tenant=p_tenant AND i.namespace=p_namespace
   AND i.workflow=p_workflow AND i.run=p_run AND i.delivery=p_delivery) THEN
   RETURN QUERY SELECT 'DUPLICATE'::text,r.version; RETURN;
 END IF;
 IF r.version<>p_version OR r.event_seq<>p_seq THEN
   RETURN QUERY SELECT 'STALE_VERSION'::text,r.version; RETURN;
 END IF;
 -- Counts are meaningful only while the run lock is held and no other
 -- role can write directly to storage tables.
 IF (SELECT count(*) FROM workflow_m1.inbox i WHERE
       i.tenant=p_tenant AND i.namespace=p_namespace
       AND i.workflow=p_workflow AND i.run=p_run)>=128
 OR (SELECT count(*) FROM workflow_m1.events e WHERE
       e.tenant=p_tenant AND e.namespace=p_namespace
       AND e.workflow=p_workflow AND e.run=p_run)>=1024
 OR (p_effect IS NOT NULL AND (SELECT count(*) FROM workflow_m1.outbox o WHERE
       o.tenant=p_tenant AND o.namespace=p_namespace
       AND o.workflow=p_workflow AND o.run=p_run)>=64)
 OR (p_timer IS NOT NULL AND (SELECT count(*) FROM workflow_m1.timers t WHERE
       t.tenant=p_tenant AND t.namespace=p_namespace
       AND t.workflow=p_workflow AND t.run=p_run)>=64) THEN
   RETURN QUERY SELECT 'QUOTA'::text,r.version; RETURN;
 END IF;
 -- Any uniqueness violation aborts the caller's whole transaction.
 INSERT INTO workflow_m1.inbox VALUES
   (p_tenant,p_namespace,p_workflow,p_run,p_delivery,r.version+1);
 UPDATE workflow_m1.runs SET
   version=r.version+1,event_seq=r.event_seq+1,phase=p_phase,
   snapshot=p_snapshot,snapshot_digest=p_digest
 WHERE tenant=p_tenant AND namespace=p_namespace
 AND workflow=p_workflow AND run=p_run
 AND generation=p_generation AND version=r.version;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'lost checkpoint CAS' USING ERRCODE='40001';
 END IF;
 INSERT INTO workflow_m1.events VALUES
   (p_tenant,p_namespace,p_workflow,p_run,r.event_seq+1,p_event,p_payload);
 IF p_effect IS NOT NULL THEN
   INSERT INTO workflow_m1.outbox
   (tenant,namespace,workflow,run,effect_key,version) VALUES
   (p_tenant,p_namespace,p_workflow,p_run,p_effect,r.version+1);
 END IF;
 IF p_timer IS NOT NULL THEN
   INSERT INTO workflow_m1.timers
   (tenant,namespace,workflow,run,timer_key,version,due_at) VALUES
   (p_tenant,p_namespace,p_workflow,p_run,p_timer,r.version+1,p_due);
 END IF;
 RETURN QUERY SELECT 'APPLIED'::text,r.version+1; RETURN;
END $$;

-- Recovery generation CAS; stale owners can no longer call apply_checkpoint.
-- Unknown outbound effects are quarantined for explicit reconciliation;
-- neither old-generation timers nor external dispatch become authorized here.
CREATE OR REPLACE FUNCTION workflow_m1.fence_recovery(
 p_tenant text,p_namespace text,p_workflow text,p_run text,
 p_expected_generation bigint
) RETURNS TABLE(result_code text,result_generation bigint)
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,workflow_m1 AS $$
DECLARE r workflow_m1.runs%ROWTYPE;
BEGIN
 IF p_expected_generation IS NULL OR p_expected_generation<=0 THEN
   RAISE EXCEPTION 'invalid generation' USING ERRCODE='22023';
 END IF;
 SELECT * INTO r FROM workflow_m1.runs
 WHERE tenant=p_tenant AND namespace=p_namespace
 AND workflow=p_workflow AND run=p_run FOR UPDATE;
 IF NOT FOUND THEN RETURN QUERY SELECT 'MISSING'::text,NULL::bigint; RETURN; END IF;
 IF r.quarantined THEN
   RETURN QUERY SELECT 'QUARANTINED'::text,r.generation; RETURN;
 END IF;
 IF r.generation<>p_expected_generation THEN
   RETURN QUERY SELECT 'FENCED'::text,r.generation; RETURN;
 END IF;
 IF r.generation=9223372036854775807 THEN
   RETURN QUERY SELECT 'QUOTA'::text,r.generation; RETURN;
 END IF;
 UPDATE workflow_m1.runs SET generation=r.generation+1 WHERE
 tenant=p_tenant AND namespace=p_namespace AND workflow=p_workflow
 AND run=p_run AND generation=r.generation;
 IF NOT FOUND THEN
   RAISE EXCEPTION 'lost recovery CAS' USING ERRCODE='40001';
 END IF;
 UPDATE workflow_m1.outbox SET status='UNKNOWN' WHERE
 tenant=p_tenant AND namespace=p_namespace AND workflow=p_workflow
 AND run=p_run AND status='IN_FLIGHT';
 RETURN QUERY SELECT 'FENCED_NEW_OWNER'::text,r.generation+1; RETURN;
END $$;

-- PostgreSQL functions otherwise grant EXECUTE to PUBLIC by default:
-- revoke inside this same migration transaction. NO runtime grants yet.
REVOKE ALL ON FUNCTION workflow_m1.apply_checkpoint(
 text,text,text,text,bigint,bigint,bigint,text,text,text,
 jsonb,text,jsonb,text,text,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION workflow_m1.fence_recovery(
 text,text,text,text,bigint) FROM PUBLIC;
COMMIT;
