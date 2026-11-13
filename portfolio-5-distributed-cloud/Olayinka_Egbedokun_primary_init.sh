#!/bin/bash
# Wavers University — Portfolio 5: primary set-up, run once by the image when
# the data directory is first created. Creates the role the replica connects
# as and allows it to stream the write-ahead log (WAL).
set -euo pipefail
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v pw="$REPLICATION_PASSWORD" <<'SQL'
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD :'pw';
SQL
echo "host replication replicator all scram-sha-256" >> "$PGDATA/pg_hba.conf"
