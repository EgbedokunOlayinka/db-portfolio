#!/bin/bash
# Wavers University — Portfolio 5: replica start-up.
# On first start, clone the primary with pg_basebackup: -X stream copies the
# WAL written during the copy, -C -S creates replication slot "replica1" so
# the primary keeps WAL the replica has not received yet, and -R writes the
# standby settings (standby.signal and primary_conninfo, which names this
# server "replica1"). Then run as a read-only hot standby.
set -euo pipefail
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  mkdir -p "$(dirname "$PGDATA")"
  PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
    -d "host=primary user=replicator application_name=replica1" \
    -D "$PGDATA" -X stream -C -S replica1 -R
fi
exec postgres
