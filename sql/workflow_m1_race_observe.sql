SELECT CASE WHEN EXISTS (
 SELECT 1 FROM pg_catalog.pg_stat_activity
 WHERE datname=pg_catalog.current_database()
 AND application_name=:'contender_app' AND wait_event_type='Lock'
) THEN 'M1_RACE_LOCK_WAIT_OBSERVED' ELSE 'M1_RACE_NOT_WAITING' END;
