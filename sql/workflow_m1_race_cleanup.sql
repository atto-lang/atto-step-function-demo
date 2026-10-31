SELECT pg_catalog.set_config('m1.race_run', :'race_run', false);
DELETE FROM workflow_m1.runs
WHERE tenant='m1-race-tenant' AND namespace='m1-race-ns'
 AND workflow='m1-race-workflow' AND run=current_setting('m1.race_run');
