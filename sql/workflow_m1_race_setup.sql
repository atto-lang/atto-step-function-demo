SELECT pg_catalog.set_config('m1.race_run', :'race_run', false);
INSERT INTO workflow_m1.runs
(tenant,namespace,workflow,run,generation,version,event_seq,phase,snapshot,snapshot_digest)
VALUES ('m1-race-tenant','m1-race-ns','m1-race-workflow',
 current_setting('m1.race_run'),7,0,0,'created','{}'::jsonb,
 'sha256:'||repeat('0',64));
