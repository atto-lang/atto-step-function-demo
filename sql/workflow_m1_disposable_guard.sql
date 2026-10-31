-- FAIL-CLOSED safety preflight. Must run immediately before mutation in
-- the same PostgreSQL session. Never a tenant/caller authentication mechanism.
-- Operator provisioned disposable PG17 DB must be named oreslang_m1_test_*
-- and carry comment: ORESLANG_M1_DISPOSABLE_DB_V1.
DO $m1_guard$
BEGIN
 IF current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
 OR current_database() !~ '^oreslang_m1_test_[a-z0-9_]+$'
 OR pg_is_in_recovery()
 OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
            WHERE r.rolname=current_user AND r.rolsuper)
 OR NOT EXISTS (
   SELECT 1 FROM pg_catalog.pg_database d
   WHERE d.datname=current_database()
   AND pg_catalog.shobj_description(d.oid,'pg_database') =
       'ORESLANG_M1_DISPOSABLE_DB_V1'
 ) THEN
   RAISE EXCEPTION
      'M1_SQL_NOT_EXECUTED: require marked non-superuser PG17 disposable DB'
     USING ERRCODE='42501';
 END IF;
END $m1_guard$;
