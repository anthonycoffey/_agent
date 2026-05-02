-- Create per-service databases on a fresh postgres volume.
-- Only runs when /var/lib/postgresql/data is empty, i.e. first boot.
-- For an already-initialized cluster, run these manually:
--   docker exec -it agent-postgres psql -U $POSTGRES_USER -c "CREATE DATABASE n8n;"

CREATE DATABASE n8n;
CREATE DATABASE langfuse;
CREATE DATABASE memory;
CREATE DATABASE evolution;
