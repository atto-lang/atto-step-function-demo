-- Transactional PostgreSQL assertions only: no crash, fsync, or native guest.
-- Run on a disposable database after applying the M1 migration.
BEGIN;
INSERT INTO workflow_m1.runs
(tenant,namespace,workflow,run,generation,version,event_seq,phase,snapshot,snapshot_digest)
VALUES
('tenant-a','ns-a','wf-a','run-a',7,0,0,'created','{}'::jsonb,'sha256:'||repeat('0',64)),
('tenant-b','ns-b','wf-b','run-b',1,0,0,'created','{}'::jsonb,'sha256:'||repeat('0',64));
-- Default PostgreSQL function EXECUTE privileges must be revoked from
-- PUBLIC before an adapter role is designed. This is only an ACL oracle:
-- RLS and authenticated guest capabilities are NOT implemented here.
DO $privilege_checks$
BEGIN
 IF EXISTS (
   SELECT 1 FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
   CROSS JOIN LATERAL pg_catalog.aclexplode(
     coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
   WHERE n.nspname='workflow_m1'
     AND p.proname IN ('apply_checkpoint','fence_recovery')
     AND a.grantee=0 AND a.privilege_type='EXECUTE'
 ) THEN
    RAISE EXCEPTION 'M1_SQL_PUBLIC_FUNCTION_EXECUTE_GRANTED';
 END IF;
 IF EXISTS (
   SELECT 1 FROM pg_catalog.pg_namespace n
   CROSS JOIN LATERAL pg_catalog.aclexplode(
     coalesce(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) a
   WHERE n.nspname='workflow_m1'
     AND a.grantee=0 AND a.privilege_type='USAGE'
 ) THEN
    RAISE EXCEPTION 'M1_SQL_PUBLIC_SCHEMA_USAGE_GRANTED';
 END IF;
END $privilege_checks$;
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
 -- The function must reject oversized JSON while preserving all records.
 -- Each nested exception block is a PostgreSQL subtransaction.
 BEGIN
   PERFORM * FROM workflow_m1.apply_checkpoint(
    'tenant-a','ns-a','wf-a','run-a',7,1,1,
    'oversize-snapshot','event-oversize-snapshot','running',
    jsonb_build_object('blob',repeat('x',65537)),
    'sha256:'||repeat('0',64),'{}'::jsonb);
   RAISE EXCEPTION 'M1_SQL_OVERSIZED_SNAPSHOT_ACCEPTED';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 BEGIN
   PERFORM * FROM workflow_m1.apply_checkpoint(
    'tenant-a','ns-a','wf-a','run-a',7,1,1,
    'oversize-event','event-oversize-event','running',
    '{}'::jsonb,'sha256:'||repeat('0',64),
    jsonb_build_object('blob',repeat('x',16385)));
   RAISE EXCEPTION 'M1_SQL_OVERSIZED_EVENT_ACCEPTED';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;
 END;
 SELECT version INTO v FROM workflow_m1.runs WHERE tenant='tenant-a';
 IF v<>1 THEN RAISE EXCEPTION 'M1_SQL_OVERSIZE_MUTATED_STATE'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.inbox WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'M1_SQL_OVERSIZE_MUTATED_INBOX'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.events WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'M1_SQL_OVERSIZE_MUTATED_EVENTS'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.outbox WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'M1_SQL_OVERSIZE_MUTATED_OUTBOX'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.timers WHERE tenant='tenant-a';
 IF ct<>1 THEN RAISE EXCEPTION 'M1_SQL_OVERSIZE_MUTATED_TIMERS'; END IF;
 UPDATE workflow_m1.outbox SET status='IN_FLIGHT' WHERE tenant='tenant-a';
 SELECT result_code,result_generation INTO rc,n
 FROM workflow_m1.fence_recovery('tenant-a','ns-a','wf-a','run-a',7);
 IF rc<>'FENCED_NEW_OWNER' OR n<>8 THEN
 RAISE EXCEPTION 'recovery failed: %, %',rc,n; END IF;
 SELECT status INTO rc FROM workflow_m1.outbox WHERE tenant='tenant-a';
 IF rc<>'UNKNOWN' THEN RAISE EXCEPTION 'ambiguous replay unsafe: %',rc; END IF;
 SELECT generation INTO n FROM workflow_m1.outbox
 WHERE tenant='tenant-a' AND effect_key='effect-1';
 IF n<>7 THEN RAISE EXCEPTION 'old effect lost source generation'; END IF;
 SELECT status,generation INTO rc,n FROM workflow_m1.timers
 WHERE tenant='tenant-a' AND timer_key='timer-1';
 IF rc<>'CANCELLED' OR n<>7 THEN
   RAISE EXCEPTION 'stale timer remains executable: %, %',rc,n;
 END IF;
 SELECT result_code INTO rc FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',7,1,1,'delivery-3','event-3','completed',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb);
 IF rc<>'FENCED' THEN RAISE EXCEPTION 'old owner accepted: %',rc; END IF;
 SELECT result_code INTO rc FROM workflow_m1.fence_recovery('tenant-a','ns-a','wf-a','run-a',7);
 IF rc<>'FENCED' THEN RAISE EXCEPTION 'old owner takeover accepted: %',rc; END IF;
 SELECT result_code,result_version INTO rc,v FROM workflow_m1.apply_checkpoint(
 'tenant-a','ns-a','wf-a','run-a',8,1,1,'delivery-4','event-4','completed',
 '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb,
 'effect-current','timer-current',now()+interval '7 minutes');
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
 -- Fault at the FINAL optional timer write, after inbox, snapshot,
 -- event and outbox have been inserted in the failed subtransaction.
 -- The duplicate timer key must roll back every earlier write.
 BEGIN
   PERFORM * FROM workflow_m1.apply_checkpoint(
     'tenant-a','ns-a','wf-a','run-a',8,2,2,
     'delivery-timer-collision','event-timer-collision','completed',
     '{}'::jsonb,'sha256:'||repeat('0',64),'{}'::jsonb,
     'effect-rolled-back','timer-1',now()+interval '10 minutes');
   RAISE EXCEPTION 'M1SQL timer conflict unexpectedly accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 SELECT version INTO v FROM workflow_m1.runs WHERE tenant='tenant-a';
 IF v<>2 THEN RAISE EXCEPTION 'timer collision mutated checkpoint version'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.inbox WHERE tenant='tenant-a';
 IF ct<>2 THEN RAISE EXCEPTION 'timer collision retained inbox'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.events WHERE tenant='tenant-a';
 IF ct<>2 THEN RAISE EXCEPTION 'timer collision retained event'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.outbox WHERE tenant='tenant-a';
 IF ct<>2 THEN RAISE EXCEPTION 'timer collision retained effect intent'; END IF;
 SELECT count(*) INTO ct FROM workflow_m1.timers WHERE tenant='tenant-a';
 IF ct<>2 THEN RAISE EXCEPTION 'timer collision retained timer'; END IF;
 -- A second takeover must PAUSE un-dispatched PREPARED work but mark only
 -- IN_FLIGHT work UNKNOWN. Old timers are cancelled, not silently fired.
 SELECT result_code,result_generation INTO rc,n
 FROM workflow_m1.fence_recovery('tenant-a','ns-a','wf-a','run-a',8);
 IF rc<>'FENCED_NEW_OWNER' OR n<>9 THEN
   RAISE EXCEPTION 'second takeover failed: %, %',rc,n;
 END IF;
 SELECT status,generation INTO rc,n FROM workflow_m1.outbox
 WHERE tenant='tenant-a' AND effect_key='effect-current';
 IF rc<>'PAUSED' OR n<>8 THEN
   RAISE EXCEPTION 'undispatched old-generation effect not paused: %, %',rc,n;
 END IF;
 SELECT status,generation INTO rc,n FROM workflow_m1.timers
 WHERE tenant='tenant-a' AND timer_key='timer-current';
 IF rc<>'CANCELLED' OR n<>8 THEN
   RAISE EXCEPTION 'old-generation armed timer not cancelled: %, %',rc,n;
 END IF;
 SELECT status INTO rc FROM workflow_m1.outbox
 WHERE tenant='tenant-a' AND effect_key='effect-1';
 IF rc<>'UNKNOWN' THEN
   RAISE EXCEPTION 'ambiguous effect incorrectly rearmed: %',rc;
 END IF;
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
