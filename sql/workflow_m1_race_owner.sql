-- Owner A holds its recovery transaction open after a successful CAS.
SELECT pg_catalog.set_config('m1.race_run', :'race_run', false);
BEGIN;
SET LOCAL synchronous_commit = on;
DO $owner$
DECLARE result text; new_generation bigint;
BEGIN
 SELECT result_code,result_generation INTO result,new_generation
 FROM workflow_m1.fence_recovery('m1-race-tenant','m1-race-ns',
  'm1-race-workflow',current_setting('m1.race_run'),7);
 IF result IS DISTINCT FROM 'FENCED_NEW_OWNER' OR new_generation IS DISTINCT FROM 8 THEN
   RAISE EXCEPTION 'M1_RACE_OWNER_CAS_FAILURE: %, %',result,new_generation;
 END IF;
END $owner$;
\echo M1_RACE_OWNER_LOCK_HELD
SELECT pg_catalog.pg_sleep(8);
COMMIT;
\echo M1_RACE_OWNER_COMMITTED
