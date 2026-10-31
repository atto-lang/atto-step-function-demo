-- Transactional PostgreSQL assertions only: no crash, fsync, or native guest.
-- Run on a disposable database after applying the M1 migration.
BEGIN;
INSERT INTO workflow_m1.runs
(tenant,namespace,workflow,run,generation,version,event_seq,phase,snapshot,snapshot_digest)
VALUES
('tenant-a','ns-a','wf-a','run-a',7,0,0,'created','{}'::jsonb,'sha256:'||repeat('0',64)),
('tenant-b','ns-b','wf-b','run-b',1,0,0,'created','{}'::jsonb,'sha256:'||repeat('0',64));
DO $check$
DECLARE rc text; v bigint; n bigint; ct bigint;
BEGIN
 SELECT result_code,result_version INTO rc,v FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',7,0,0,'delivery-1','event-1','running',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb,
 'effect-1','timer-1',now()+interval '5 minutes');
 IF rc<>'APPLIED' OR v<>1 THEN RAISE EXCEPTION 'apply failed: %, %',rc,v; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.inbox WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'inbox absent'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.events WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'event absent'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.outbox WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'outbox absent'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.timers WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'timer absent'; END IF;
 SELECT result_code INTO rc FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',7,0,0,'delivery-1','event-1','running',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 IF rc<>'DUPLICATE' THEN RAISE EXCEPTION 'dedup failed: %',rc; END IF;
 SELECT result_code INTO rc FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',7,0,0,'delivery-2','event-2','running',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 IF rc<>'STALE_VERSION' THEN RAISE EXCEPTION 'stale accepted: %',rc; END IF;
 SELECT result_code INTO rc FROM workflow_m1.apply_checkpoint(
 'tenant-x','ns-a','wf-a','run-a',7,0,0,'foreign','event-x','running',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 IF rc<>'MISSING' THEN RAISE EXCEPTION 'foreign accepted: %',rc; END IF;
 UPDATE workflow_m1.outbox SET status='IN_FLIGHT' WHERE tenant='tenant-a';
 SELECT result_code,result_generation INTO rc,n
 FROM workflow_m1.fence_recovery('tenant-a','ns-a','wf-a','run-a',7);
 IF rc<>'FENCED_NEW_OWNER' OR n<>8 THEN
 RAISE EXCEPTION 'recovery failed: %, %',rc,n; END IF;
 SELECT status INTO rc FROM workflow_m1.outbox WHERE tenant='tenant-a';
 IF rc<>'UNKNOWN' THEN RAISE EXCEPTION 'ambiguous replay unsafe: %',rc; END IF;
 SELECT result_code INTO rc FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',7,1,1,'delivery-3','event-3','completed',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 IF rc<>'FENCED' THEN RAISE EXCEPTION 'old owner accepted: %',rc; END IF;
 SELECT result_code INTO rc FROM workflow_m1.fence_recovery('tenant-a','ns-a','wf-a','run-a',7);
 IF rc<>'FENCED' THEN RAISE EXCEPTION 'old owner takeover accepted: %',rc; END IF;
 SELECT result_code,result_version INTO rc,v FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',8,1,1,'delivery-4','event-4','completed',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 IF rc<>'APPLIED' OR v<>2 THEN RAISE EXCEPTION 'new owner rejected: %, %',rc,v; END IF;
 BEGIN
 PERFORM * FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',8,2,2,'delivery-5','event-1','completed',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 RAISE EXCEPTION 'expected duplicate event unique violation';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 SELECT version INTO v FROM workflow_m1.runs WHERE tenant='tenant-a';
 IF v<>2 THEN RAISE EXCEPTION 'failed TX partially updated version'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.inbox
 WHERE tenant='tenant-a' AND delivery='delivery-5';
 IF ct<>0 THEN RAISE EXCEPTION 'failed TX retained inbox'; END IF;
 UPDATE workflow_m1.runs SET quarantined=true WHERE tenant='tenant-b';
 SELECT result_code INTO rc FROM workflow_m1.apply_checkpoint(
 'tenant-b','ns-b','wf-b','run-b',1,0,0,'d-b','e-b','running',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 IF rc<>'QUARANTINED' THEN RAISE EXCEPTION 'quarantine bypass: %',rc; END IF;
 SELECT version INTO v FROM workflow_m1.runs WHERE tenant='tenant-a';
 IF v<>2 THEN RAISE EXCEPTION 'healthy tenant disturbed'; END IF;
 RAISE NOTICE 'M1_SQL_TRANSACTION_ASSERTIONS_PASS (no crash or guest proof)';
END $check$;
ROLLBACK;
