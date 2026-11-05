-- Third independent PostgreSQL session, after both owner and contender exit.
-- This tests committed storage state, not crash durability or a guest adapter.
SELECT pg_catalog.set_config('m1.race_run', :'race_run', false) AS run_setting \gset
DO $verify$
DECLARE current_generation bigint;
        current_version bigint;
        current_event_seq bigint;
        current_phase text;
        current_quarantine boolean;
BEGIN
 SELECT generation, version, event_seq, phase, quarantined
 INTO current_generation, current_version, current_event_seq, current_phase, current_quarantine
 FROM workflow_m1.runs
 WHERE tenant='m1-race-tenant' AND namespace='m1-race-ns'
 AND workflow='m1-race-workflow' AND run=current_setting('m1.race_run');
 IF NOT FOUND OR current_generation IS DISTINCT FROM 8
 OR current_version IS DISTINCT FROM 0
 OR current_event_seq IS DISTINCT FROM 0
 OR current_phase IS DISTINCT FROM 'created'
 OR current_quarantine IS DISTINCT FROM false THEN
   RAISE EXCEPTION 'M1_RACE_BAD_POSTCOMMIT_RUN_STATE: generation=%, version=%',
     current_generation, current_version;
 END IF;
 IF EXISTS(SELECT 1 FROM workflow_m1.inbox WHERE tenant='m1-race-tenant'
   AND namespace='m1-race-ns' AND workflow='m1-race-workflow'
   AND run=current_setting('m1.race_run'))
 OR EXISTS(SELECT 1 FROM workflow_m1.events WHERE tenant='m1-race-tenant'
   AND namespace='m1-race-ns' AND workflow='m1-race-workflow'
   AND run=current_setting('m1.race_run'))
 OR EXISTS(SELECT 1 FROM workflow_m1.outbox WHERE tenant='m1-race-tenant'
   AND namespace='m1-race-ns' AND workflow='m1-race-workflow'
   AND run=current_setting('m1.race_run'))
 OR EXISTS(SELECT 1 FROM workflow_m1.timers WHERE tenant='m1-race-tenant'
   AND namespace='m1-race-ns' AND workflow='m1-race-workflow'
   AND run=current_setting('m1.race_run')) THEN
   RAISE EXCEPTION 'M1_RACE_POSTCOMMIT_STALE_EFFECT_OR_EVENT';
 END IF;
END $verify$;
\echo M1_RACE_POSTCOMMIT_DURABLE_STATE_OK
