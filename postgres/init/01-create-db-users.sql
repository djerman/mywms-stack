\set ON_ERROR_STOP on

-- 1) Улоге (ово сме у трансакцији)
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mywms') THEN
      CREATE ROLE mywms LOGIN PASSWORD 'mywms';
   END IF;
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'reportserver') THEN
      CREATE ROLE reportserver LOGIN PASSWORD 'reportserver';
   END IF;
END $$;

-- 2) Базе (НЕ сме у трансакцији → зато НЕ користимо DO)
--    Користимо psql \gexec: резултат SELECT-а постаје SQL који се извршава.
SELECT 'CREATE DATABASE mywms OWNER mywms'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mywms');
\gexec

SELECT 'CREATE DATABASE reportserver OWNER reportserver'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'reportserver');
\gexec

