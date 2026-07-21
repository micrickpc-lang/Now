-- Local-development roles. Production credentials come from a secret manager.
CREATE EXTENSION IF NOT EXISTS postgis;
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'seychas_migrator') THEN
    CREATE ROLE seychas_migrator LOGIN PASSWORD 'local_migrator_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'seychas_app') THEN
    CREATE ROLE seychas_app LOGIN PASSWORD 'local_app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
END $$;
GRANT CONNECT ON DATABASE seychas TO seychas_migrator, seychas_app;
GRANT USAGE, CREATE ON SCHEMA public TO seychas_migrator;
GRANT USAGE ON SCHEMA public TO seychas_app;
ALTER DEFAULT PRIVILEGES FOR ROLE seychas_migrator IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO seychas_app;
ALTER DEFAULT PRIVILEGES FOR ROLE seychas_migrator IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO seychas_app;
