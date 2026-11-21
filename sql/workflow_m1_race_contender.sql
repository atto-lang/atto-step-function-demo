-- Owner B blocks on A's run lock; then observes epoch 8 and must lose.
SELECT pg_catalog.set_config('m1.race_run', :'race_run', false);
SET lock_timeout = '15s';
DO $contender$
DECLARE result text; gen bigint; count_inbox bigint;
BEGIN
 SELECT result_code,result_generation INTO result,gen
 FROM workflow_m1.fence_recovery('m1-race-tenant','m1-race-ns',
  'm1-race-workflow',current_setting('m1.race_run'),7);
 IF result IS DISTINCT FROM 'FENCED' OR gen IS DISTINCT FROM 8 THEN
   RAISE EXCEPTION 'M1_RACE_STALE_CAS_ACCEPTED: %, %',result,gen;
 END IF;
 SELECT result_code INTO result FROM workflow_m1.apply_checkpoint(
  'm1-race-tenant','m1-race-ns','m1-race-workflow',
  current_setting('m1.race_run'),7,0,0,
  'stale-delivery','stale-event','running','{}'::jsonb,
  'sha256:'||repeat('0',64),'{}'::jsonb);
 IF result IS DISTINCT FROM 'FENCED' THEN
   RAISE EXCEPTION 'M1_RACE_STALE_WRITE_ACCEPTED: %',result;
 END IF;
 SELECT count(*) INTO count_inbox FROM workflow_m1.inbox
 WHERE tenant='m1-race-tenant' AND namespace='m1-race-ns'
 AND workflow='m1-race-workflow' AND run=current_setting('m1.race_run');
 IF count_inbox <> 0 THEN
   RAISE EXCEPTION 'M1_RACE_STALE_INBOX_ADMITTED: %',count_inbox;
 END IF;
END $contender$;
\echo M1_RACE_CONTENDER_FENCED
